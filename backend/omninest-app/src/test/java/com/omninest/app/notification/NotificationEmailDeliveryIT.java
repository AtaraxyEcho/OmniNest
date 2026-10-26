package com.omninest.app.notification;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.assertj.core.api.Assertions.catchThrowable;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.omninest.OmniNestApplication;
import com.omninest.common.security.CredentialCipher;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.common.storage.ObjectStorageKey;
import com.omninest.modules.configcenter.service.ConfigCenterService;
import com.omninest.modules.notification.config.NotificationEmailRuntimeConfig;
import com.omninest.modules.notification.config.NotificationEmailRuntimeConfig.MessageFormat;
import com.omninest.modules.notification.service.NotificationEmailRenderer;
import com.omninest.modules.notification.service.NotificationEmailSender;
import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.time.Instant;
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
import org.springframework.mail.MailException;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.testcontainers.utility.MountableFile;
import org.springframework.test.annotation.DirtiesContext;

/**
 * 通知邮件通道在真实 SMTP 服务上的投递验证。
 *
 * <p>SMTP 参数走配置中心（口令密文落库、读取时解回明文），发送要真建一条 TCP 连接把消息
 * 交出去，这两点用 Mock 永远证明不了。这里起三个 Mailpit：一个开放投递，另一个强制登录，
 * 第三个带运行期自签证书，因此既能确认消息确实落到收件端、多部件正文与转义形态符合预期，
 * 也能证明凭据真的被发出，以及证书校验与"必须加密"这两道闸门在服务端不配合时确实会失败。</p>
 *
 * <p>证书不落仓库，由 {@link NotificationEmailTestCertificates} 在测试启动时现生成，退出即删。
 * 隐式 TLS（465 一类端口）不在这里验证：Mailpit 的 {@code --smtp} 只接受 {@code ip:port} 绑定，
 * 没有免 STARTTLS 的 TLS 监听口，因此 {@code security=SSL} 只能断言"不会静默退回明文"，
 * 真正握手成功需要一台隐式 TLS 服务。</p>
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
@DirtiesContext(classMode = DirtiesContext.ClassMode.AFTER_CLASS)
@Testcontainers(disabledWithoutDocker = true)
@Import(NotificationEmailDeliveryIT.ExternalDependencyOverrides.class)
class NotificationEmailDeliveryIT {

    private static final String POSTGRES_IMAGE = "postgres:18-alpine";
    private static final String MAILPIT_IMAGE = "axllent/mailpit:latest";
    private static final String RECIPIENT = "alex@example.test";
    private static final String SMTP_USER = "it-smtp-user";
    private static final String SMTP_PASSWORD = "it-smtp-" + UUID.randomUUID();

    /** 强制登录收件端用的凭据文件：运行期写在临时目录，不入库。 */
    private static final Path AUTH_FILE = writeAuthFile();

    @Container
    private static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>(POSTGRES_IMAGE)
            .withDatabaseName("omninest_email_it")
            .withUsername("omninest")
            .withPassword("omninest");

    /** 开放投递的收件端：不 advertise AUTH，因此这段配置只用匿名中继形态。 */
    @Container
    private static final GenericContainer<?> MAILPIT = new GenericContainer<>(MAILPIT_IMAGE)
            .withExposedPorts(1025, 8025);

    /** 要求 SMTP 登录的收件端，用来证明凭据真的被发出而不是被忽略。 */
    @Container
    private static final GenericContainer<?> MAILPIT_AUTH = new GenericContainer<>(MAILPIT_IMAGE)
            .withExposedPorts(1025, 8025)
            .withCopyFileToContainer(MountableFile.forHostPath(AUTH_FILE), "/tmp/htpasswd")
            // 镜像的 ENTRYPOINT 已是 /mailpit，这里只给参数，重复写可执行文件会让容器起不来。
            .withCommand("-s", "[::]:1025", "--smtp-auth-file", "/tmp/htpasswd",
                    "--smtp-auth-allow-insecure");

    /** 提供 STARTTLS 的收件端：自签证书，用来区分"链校验失败"与"根本连不上"。 */
    @Container
    private static final GenericContainer<?> MAILPIT_TLS = startTlsMailpit();

    @Autowired
    private ConfigCenterService configCenterService;

    @Autowired
    private CredentialCipher credentialCipher;

    @Autowired
    private NotificationEmailRuntimeConfig runtimeConfig;

    @Autowired
    private NotificationEmailSender emailSender;

    @Autowired
    private NotificationEmailRenderer emailRenderer;

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @DynamicPropertySource
    static void registerDatabaseProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", POSTGRES::getJdbcUrl);
        registry.add("spring.datasource.username", POSTGRES::getUsername);
        registry.add("spring.datasource.password", POSTGRES::getPassword);
    }

    @Test
    @DisplayName("敏感口令密文落库、读取解回明文，并按配置中心的参数真发到 SMTP")
    void deliversThroughConfiguredSmtpServer() throws Exception {
        configureOpenRelay();
        String secret = "provider-" + UUID.randomUUID();
        configCenterService.seedSystemConfigValue(
                "notification.email.password", credentialCipher.encrypt(secret));

        assertThat(runtimeConfig.configured()).isTrue();
        assertThat(runtimeConfig.password()).isEqualTo(secret);
        String storedPassword = jdbcTemplate.queryForObject(
                "SELECT config_value FROM omni.config_entries WHERE config_key = 'notification.email.password'",
                String.class);
        assertThat(storedPassword).isNotEqualTo(secret).isNotBlank();

        String marker = "email-it-" + UUID.randomUUID();
        emailSender.send(RECIPIENT, "通知邮件投递验证 " + marker, "正文：备份任务已完成 " + marker, null);

        String stored = fetchStoredMessage(MAILPIT, marker);
        assertThat(stored)
                .contains("notify@omninest.test")
                .contains(RECIPIENT)
                .contains("备份任务已完成 " + marker);
    }

    @Test
    @DisplayName("RICH 投递同时带纯文本与 HTML 部件，用户文本只剩转义形态")
    void richDeliveryCarriesPlainTextAlternativeAndEscapesUserData() throws Exception {
        configureOpenRelay();
        configCenterService.seedSystemConfigValue("notification.email.format", "RICH");
        configCenterService.seedSystemConfigValue(
                "notification.email.web-base-url", "https://nest.example.test");
        assertThat(runtimeConfig.format()).isEqualTo(MessageFormat.RICH);

        String marker = "rich-it-" + UUID.randomUUID();
        String title = "导入完成 " + marker;
        String hostileBody = "已导入 <b>movie.nfo</b></td></tr>"
                + "<script>document.write('x')</script>";
        var rendered = emailRenderer.render(
                title,
                title,
                hostileBody,
                "任务完成",
                Instant.parse("2026-10-20T02:00:00Z"),
                "https://nest.example.test",
                MessageFormat.RICH);
        emailSender.send(RECIPIENT, rendered.subject(), rendered.plainText(), rendered.html());

        String stored = fetchStoredMessage(MAILPIT, marker);
        assertThat(stored)
                // 纯文本部件带原样文本，HTML 部件只以转义形态出现：两者都在才说明降级成立。
                .contains("已导入")
                .contains("&lt;b&gt;movie.nfo&lt;/b&gt;")
                .contains("nest.example.test")
                .doesNotContain("<img");
    }

    @Test
    @DisplayName("服务端要求登录：正确凭据投递成功，错误凭据失败且不落信")
    void authenticationIsEnforcedByTheServer() throws Exception {
        configCenterService.seedSystemConfigValue("notification.email.enabled", "true");
        configCenterService.seedSystemConfigValue("notification.email.host", MAILPIT_AUTH.getHost());
        configCenterService.seedSystemConfigValue(
                "notification.email.port", String.valueOf(MAILPIT_AUTH.getMappedPort(1025)));
        configCenterService.seedSystemConfigValue("notification.email.security", "NONE");
        configCenterService.seedSystemConfigValue("notification.email.trust-hosts", "");
        configCenterService.seedSystemConfigValue("notification.email.from", "notify@omninest.test");
        configCenterService.seedSystemConfigValue("notification.email.format", "PLAIN");
        configCenterService.seedSystemConfigValue("notification.email.web-base-url", "");
        configCenterService.seedSystemConfigValue("notification.email.username", SMTP_USER);
        configCenterService.seedSystemConfigValue(
                "notification.email.password", credentialCipher.encrypt(SMTP_PASSWORD));

        String accepted = "auth-ok-" + UUID.randomUUID();
        emailSender.send(RECIPIENT, "登录投递验证 " + accepted, "正文 " + accepted, null);
        assertThat(get(MAILPIT_AUTH, "/api/v1/messages")).contains(accepted);

        String rejected = "auth-bad-" + UUID.randomUUID();
        configCenterService.seedSystemConfigValue(
                "notification.email.password", credentialCipher.encrypt("wrong-" + UUID.randomUUID()));
        assertThatThrownBy(() ->
                emailSender.send(RECIPIENT, "登录失败验证 " + rejected, "正文 " + rejected, null))
                .isInstanceOf(RuntimeException.class);
        assertThat(get(MAILPIT_AUTH, "/api/v1/messages")).doesNotContain(rejected);
    }

    @Test
    @DisplayName("要求加密时不静默降明文：明文服务端在 STARTTLS 与 SSL 下都投递失败")
    void tlsModesRefusePlaintextServer() throws Exception {
        configureOpenRelay();
        configCenterService.seedSystemConfigValue("notification.email.security", "STARTTLS");
        String refused = "starttls-refused-" + UUID.randomUUID();
        Throwable startTlsFailure = catchThrowable(() ->
                emailSender.send(RECIPIENT, "STARTTLS 降密验证 " + refused, "正文 " + refused, null));
        assertThat(startTlsFailure).isInstanceOf(MailException.class);
        assertThat(causeChain(startTlsFailure)).containsIgnoringCase("tls");

        configCenterService.seedSystemConfigValue("notification.email.security", "SSL");
        String sslRefused = "ssl-refused-" + UUID.randomUUID();
        assertThatThrownBy(() ->
                emailSender.send(RECIPIENT, "隐式 TLS 降密验证 " + sslRefused, "正文 " + sslRefused, null))
                .isInstanceOf(MailException.class);

        String listed = get(MAILPIT, "/api/v1/messages");
        assertThat(listed).doesNotContain(refused).doesNotContain(sslRefused);
    }

    @Test
    @DisplayName("自签证书默认拒绝：写进信任清单后才投递，失败时一封都不落信")
    void selfSignedCertRequiresTrustList() throws Exception {
        configureTlsRelay("");
        String rejected = "tls-untrusted-" + UUID.randomUUID();
        Throwable failure = catchThrowable(() ->
                emailSender.send(RECIPIENT, "证书校验验证 " + rejected, "正文 " + rejected, null));
        assertThat(failure).isInstanceOf(MailException.class);
        assertThat(causeChain(failure))
                .as("失败原因应是 TLS 校验，而不是端口不通之类的环境问题：%s", causeChain(failure))
                .containsAnyOf("SSLHandshakeException", "certificate");
        assertThat(get(MAILPIT_TLS, "/api/v1/messages")).doesNotContain(rejected);

        configCenterService.seedSystemConfigValue(
                "notification.email.trust-hosts", MAILPIT_TLS.getHost());
        String accepted = "tls-trusted-" + UUID.randomUUID();
        emailSender.send(RECIPIENT, "证书信任投递 " + accepted, "正文 " + accepted, null);
        assertThat(fetchStoredMessage(MAILPIT_TLS, accepted))
                .contains("证书信任投递 " + accepted);
    }

    private void configureOpenRelay() {
        configureRelay(MAILPIT, "NONE", "");
    }

    private void configureTlsRelay(String trustHosts) {
        configureRelay(MAILPIT_TLS, "STARTTLS", trustHosts);
    }

    /**
     * 把 SMTP 参数指向指定收件端。
     */
    private void configureRelay(GenericContainer<?> mailpit, String security, String trustHosts) {
        configCenterService.seedSystemConfigValue("notification.email.enabled", "true");
        configCenterService.seedSystemConfigValue("notification.email.host", mailpit.getHost());
        configCenterService.seedSystemConfigValue(
                "notification.email.port", String.valueOf(mailpit.getMappedPort(1025)));
        configCenterService.seedSystemConfigValue("notification.email.security", security);
        configCenterService.seedSystemConfigValue("notification.email.trust-hosts", trustHosts);
        configCenterService.seedSystemConfigValue("notification.email.from", "notify@omninest.test");
        configCenterService.seedSystemConfigValue("notification.email.username", "");
        configCenterService.seedSystemConfigValue("notification.email.password", "");
        configCenterService.seedSystemConfigValue("notification.email.format", "PLAIN");
        configCenterService.seedSystemConfigValue("notification.email.web-base-url", "");
    }

    /**
     * 拼接异常链上的类名与消息，用于按"失败原因"而不是"是否失败"下断言。
     *
     * <p>只看类型会把端口不通、容器没起来这类环境问题也当成校验生效，因此必须把链上的
     * TLS 相关字样锁住。</p>
     */
    private static String causeChain(Throwable error) {
        StringBuilder text = new StringBuilder();
        Throwable current = error;
        while (current != null) {
            text.append(current.getClass().getName()).append(": ")
                    .append(current.getMessage()).append('\n');
            if (current.getCause() == current) {
                break;
            }
            current = current.getCause();
        }
        return text.toString();
    }

    /**
     * 取回包含标记的那条消息详情，并把 JSON 转义还原成正文原样。
     *
     * <p>清单里的消息 ID 键是 {@code "ID"}，值大小写敏感，因此定位与截取都用原文；Mailpit 的
     * JSON 会把 {@code < > &} 输出成 {@code \u003c} 一类转义，不还原就没法按"是否仍是转义形态"
     * 下断言。</p>
     */
    private String fetchStoredMessage(GenericContainer<?> mailpit, String marker) throws Exception {
        String listed = get(mailpit, "/api/v1/messages");
        int markerAt = listed.indexOf(marker);
        assertThat(markerAt).as("收件端应已收到带标记的消息，清单：%s", listed).isGreaterThan(0);
        int idAt = listed.lastIndexOf("\"ID\":\"", markerAt);
        assertThat(idAt).as("清单里应能定位消息 ID：%s", listed).isGreaterThanOrEqualTo(0);
        int valueStart = idAt + "\"ID\":\"".length();
        String id = listed.substring(valueStart, listed.indexOf('"', valueStart));
        return unescapeJson(get(mailpit, "/api/v1/message/" + id));
    }

    private String unescapeJson(String value) {
        return value.replace("\\u003c", "<")
                .replace("\\u003e", ">")
                .replace("\\u0026", "&");
    }

    private String get(GenericContainer<?> mailpit, String path) throws Exception {
        HttpResponse<String> response = HttpClient.newHttpClient().send(
                HttpRequest.newBuilder(URI.create("http://" + mailpit.getHost() + ":"
                        + mailpit.getMappedPort(8025) + path))
                        .timeout(Duration.ofSeconds(10))
                        .GET()
                        .build(),
                HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
        assertThat(response.statusCode()).isEqualTo(200);
        return response.body();
    }

    private static GenericContainer<?> startTlsMailpit() {
        GenericContainer<?> mailpit = new GenericContainer<>(MAILPIT_IMAGE)
                .withExposedPorts(1025, 8025);
        NotificationEmailTestCertificates.CertificatePair certificate =
                NotificationEmailTestCertificates.generateLocalhostPair(mailpit.getHost());
        return mailpit
                .withCopyFileToContainer(
                        MountableFile.forHostPath(certificate.certificate()), "/tmp/fullchain.pem")
                .withCopyFileToContainer(
                        MountableFile.forHostPath(certificate.privateKey()), "/tmp/privkey.pem")
                .withCommand("-s", "[::]:1025", "--smtp-tls-cert", "/tmp/fullchain.pem",
                        "--smtp-tls-key", "/tmp/privkey.pem");
    }

    private static Path writeAuthFile() {
        try {
            Path file = Files.createTempFile("omninest-mailpit-htpasswd", ".txt");
            Files.writeString(file, SMTP_USER + ":" + SMTP_PASSWORD + System.lineSeparator());
            file.toFile().deleteOnExit();
            return file;
        } catch (IOException exception) {
            throw new IllegalStateException("无法写入测试 SMTP 凭据文件", exception);
        }
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
