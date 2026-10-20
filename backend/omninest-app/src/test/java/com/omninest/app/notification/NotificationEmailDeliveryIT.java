package com.omninest.app.notification;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.omninest.OmniNestApplication;
import com.omninest.common.security.CredentialCipher;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.common.storage.ObjectStorageKey;
import com.omninest.modules.configcenter.service.ConfigCenterService;
import com.omninest.modules.notification.config.NotificationEmailRuntimeConfig;
import com.omninest.modules.notification.service.NotificationEmailSender;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.UUID;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.amqp.core.AmqpAdmin;
import org.springframework.amqp.rabbit.config.SimpleRabbitListenerContainerFactory;
import org.springframework.beans.BeansException;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.config.BeanPostProcessor;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.context.annotation.Primary;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * 通知邮件通道在真实 SMTP 服务上的投递验证。
 *
 * <p>SMTP 参数走配置中心（口令密文落库、读取时解回明文），发送要真建一条 TCP 连接把消息
 * 交出去，这两点用 Mock 永远证明不了。这里用 Mailpit 当收件端：它同时提供 SMTP 端口和
 * 查询已收消息的 HTTP 接口，因此能确认消息确实离开本进程且参数、正文都按预期成形。</p>
 *
 * @author OmniNest
 */
@SpringBootTest(
        classes = OmniNestApplication.class,
        webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = {
                "spring.rabbitmq.dynamic=false",
                "spring.rabbitmq.listener.simple.auto-startup=false",
                "spring.main.allow-bean-definition-overriding=true",
                "omninest.messaging.rabbit.backlog-monitoring-enabled=false",
                "omninest.redis.capacity.monitoring-enabled=false",
                "omninest.runtime.role=api",
                "omninest.runtime.embedded-worker-enabled=false",
                "omninest.setup.persistent-state-enabled=false",
                "file.local-media.enabled=false",
                "omninest.clamav.enabled=false",
                // 集成测试专用口令加密键（32 字节 Base64），只为让敏感配置能真实加解密。
                "omninest.security.credential-encryption-key=b21uaW5lc3QtZW1haWwtaXQtY3JlZGVudGlhbC1rZXk=",
                "omninest.search.index-path=${java.io.tmpdir}/omninest-email-it"
        }
)
@ActiveProfiles("dev")
@Testcontainers(disabledWithoutDocker = true)
@Import(NotificationEmailDeliveryIT.ExternalDependencyOverrides.class)
class NotificationEmailDeliveryIT {

    private static final String POSTGRES_IMAGE = "postgres:18-alpine";
    private static final String MAILPIT_IMAGE = "axllent/mailpit:latest";
    private static final String RECIPIENT = "alex@example.test";

    @Container
    private static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>(POSTGRES_IMAGE)
            .withDatabaseName("omninest_email_it")
            .withUsername("omninest")
            .withPassword("omninest");

    @Container
    private static final GenericContainer<?> MAILPIT = new GenericContainer<>(MAILPIT_IMAGE)
            .withExposedPorts(1025, 8025);

    @Autowired
    private ConfigCenterService configCenterService;

    @Autowired
    private CredentialCipher credentialCipher;

    @Autowired
    private NotificationEmailRuntimeConfig runtimeConfig;

    @Autowired
    private NotificationEmailSender emailSender;

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @DynamicPropertySource
    static void registerDatabaseProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", POSTGRES::getJdbcUrl);
        registry.add("spring.datasource.username", POSTGRES::getUsername);
        registry.add("spring.datasource.password", POSTGRES::getPassword);
    }

    @Test
    @DisplayName("口令密文落库、读取解回明文，并按配置中心的参数真发到 SMTP")
    void deliversThroughConfiguredSmtpServer() throws Exception {
        String secret = "it-smtp-" + UUID.randomUUID();
        configCenterService.seedSystemConfigValue("notification.email.enabled", "true");
        configCenterService.seedSystemConfigValue("notification.email.host", MAILPIT.getHost());
        configCenterService.seedSystemConfigValue(
                "notification.email.port",
                String.valueOf(MAILPIT.getMappedPort(1025)));
        configCenterService.seedSystemConfigValue("notification.email.username", "it-user");
        configCenterService.seedSystemConfigValue(
                "notification.email.password",
                credentialCipher.encrypt(secret));
        configCenterService.seedSystemConfigValue("notification.email.from", "notify@omninest.test");
        configCenterService.seedSystemConfigValue("notification.email.starttls", "false");

        assertThat(runtimeConfig.configured()).isTrue();
        assertThat(runtimeConfig.password()).isEqualTo(secret);
        String storedPassword = jdbcTemplate.queryForObject(
                "SELECT config_value FROM omni.config_entries WHERE config_key = 'notification.email.password'",
                String.class);
        assertThat(storedPassword).isNotEqualTo(secret).isNotBlank();

        String marker = "email-it-" + UUID.randomUUID();
        emailSender.send(RECIPIENT, "通知邮件投递验证 " + marker, "正文：备份任务已完成 " + marker);

        String stored = get("/api/v1/message/" + markerId(marker));
        assertThat(stored)
                .contains("notify@omninest.test")
                .contains(RECIPIENT)
                .contains("备份任务已完成 " + marker);
    }

    private String get(String path) throws Exception {
        HttpResponse<String> response = HttpClient.newHttpClient().send(
                HttpRequest.newBuilder(URI.create("http://" + MAILPIT.getHost() + ":"
                        + MAILPIT.getMappedPort(8025) + path))
                        .timeout(Duration.ofSeconds(10))
                        .GET()
                        .build(),
                HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
        assertThat(response.statusCode()).isEqualTo(200);
        return response.body();
    }

    /**
     * 从 Mailpit 消息清单里挑出包含标记的消息 ID。
     *
     * <p>清单是 JSON，这里只按 {@code "ID":"..."} 片段定位，不为一条测试额外引入解析依赖。</p>
     */
    private String markerId(String marker) throws Exception {
        String listed = get("/api/v1/messages");
        int markerAt = listed.indexOf(marker);
        assertThat(markerAt).isGreaterThan(0);
        int idAt = listed.lastIndexOf("\"ID\":\"", markerAt);
        assertThat(idAt).isGreaterThanOrEqualTo(0);
        int valueStart = idAt + "\"ID\":\"".length();
        return listed.substring(valueStart, listed.indexOf('"', valueStart));
    }

    @TestConfiguration
    static class ExternalDependencyOverrides {

        @Bean
        @Primary
        ObjectStorageClient objectStorageClient() {
            ObjectStorageClient client = mock(ObjectStorageClient.class);
            when(client.objectExists(any(ObjectStorageKey.class))).thenReturn(true);
            return client;
        }

        @Bean
        @Primary
        AmqpAdmin amqpAdmin() {
            return mock(AmqpAdmin.class);
        }

        @Bean
        static BeanPostProcessor disableRabbitListenerStartup() {
            return new BeanPostProcessor() {
                @Override
                public Object postProcessBeforeInitialization(Object bean, String beanName)
                        throws BeansException {
                    if (bean instanceof SimpleRabbitListenerContainerFactory factory) {
                        factory.setAutoStartup(false);
                    }
                    return bean;
                }
            };
        }
    }
}
