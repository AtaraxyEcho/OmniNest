package com.omninest.app.auth;

import static org.assertj.core.api.Assertions.assertThat;
import static org.junit.jupiter.api.Assertions.assertTimeoutPreemptively;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.omninest.OmniNestApplication;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.common.storage.ObjectStorageKey;
import com.omninest.modules.user.dto.AuthTokenResponse;
import com.omninest.modules.user.dto.LoginRequest;
import com.omninest.modules.user.service.AuthService;
import java.time.Duration;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
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
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.annotation.DirtiesContext;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.testcontainers.utility.DockerImageName;

/**
 * 同平台单设备互斥的真库回归测试。
 *
 * <p>互斥吊销走 {@code @Modifying} 批量更新，必须由事务承载：一旦把它挪到事务外，
 * 第二次同平台登录直接抛 {@code TransactionRequiredException} 变成 500，用户换设备
 * 或换浏览器就登不进来。单元测试桩掉了仓储，测不出这条边界，因此用真库跑两次登录。</p>
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
                "omninest.search.index-path=${java.io.tmpdir}/omninest-auth-mutex-it"
        }
)
@ActiveProfiles("dev")
@DirtiesContext(classMode = DirtiesContext.ClassMode.AFTER_CLASS)
@Testcontainers(disabledWithoutDocker = true)
@Import(AuthSamePlatformMutexIT.ExternalDependencyOverrides.class)
class AuthSamePlatformMutexIT {

    private static final String POSTGRES_IMAGE = "postgres:18-alpine";
    private static final String USERNAME = "mutex-it";
    private static final String PASSWORD = "Mutex-it#Pass-2026";
    private static final UUID USER_ID = UUID.fromString("10000000-0000-0000-0000-00000000c001");

    @Container
    private static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>(POSTGRES_IMAGE)
            .withDatabaseName("omninest_auth_mutex_it")
            .withUsername("omninest")
            .withPassword("omninest");

    @Container
    private static final GenericContainer<?> REDIS =
            new GenericContainer<>(DockerImageName.parse("redis:7-alpine")).withExposedPorts(6379);

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @Autowired
    private AuthService authService;

    @Autowired
    private PasswordEncoder passwordEncoder;

    @DynamicPropertySource
    static void registerContainerProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", POSTGRES::getJdbcUrl);
        registry.add("spring.datasource.username", POSTGRES::getUsername);
        registry.add("spring.datasource.password", POSTGRES::getPassword);
        registry.add("spring.data.redis.host", REDIS::getHost);
        registry.add("spring.data.redis.port", () -> REDIS.getMappedPort(6379));
    }

    @BeforeEach
    void seedAccount() {
        jdbcTemplate.update("delete from omni.auth_active_sessions where user_id = ?", USER_ID);
        jdbcTemplate.update("delete from omni.auth_session_revocations where user_id = ?", USER_ID);
        jdbcTemplate.update("delete from omni.auth_user_roles where user_id = ?", USER_ID);
        jdbcTemplate.update("delete from omni.auth_users where id = ?", USER_ID);
        jdbcTemplate.update(
                "insert into omni.auth_users (id, username, password_hash, status) values (?, ?, ?, 'ACTIVE')",
                USER_ID, USERNAME, passwordEncoder.encode(PASSWORD));
    }

    @Test
    @DisplayName("同平台第二次登录：签发成功且旧会话被吊销，只剩一条未撤销会话")
    void secondSamePlatformLoginRevokesPreviousSession() {
        assertTimeoutPreemptively(Duration.ofSeconds(30), () -> {
            AuthTokenResponse first = login("device-first");
            AuthTokenResponse second = login("device-second");

            assertThat(first.accessToken()).isNotBlank();
            assertThat(second.accessToken()).isNotBlank();

            Integer active = jdbcTemplate.queryForObject(
                    "select count(*) from omni.auth_active_sessions "
                            + "where user_id = ? and client_platform = 'web' and revoked_at is null",
                    Integer.class, USER_ID);
            Integer revoked = jdbcTemplate.queryForObject(
                    "select count(*) from omni.auth_active_sessions "
                            + "where user_id = ? and client_platform = 'web' and revoked_at is not null",
                    Integer.class, USER_ID);

            assertThat(active).isEqualTo(1);
            assertThat(revoked).isEqualTo(1);
            assertThat(jdbcTemplate.queryForObject(
                    "select revoke_reason from omni.auth_active_sessions "
                            + "where user_id = ? and revoked_at is not null",
                    String.class, USER_ID)).contains("同平台新设备登录");
        });
    }

    @Test
    @DisplayName("跨平台登录互不影响：web 与 android 各自保留一条活动会话")
    void differentPlatformsKeepTheirOwnSessions() {
        assertTimeoutPreemptively(Duration.ofSeconds(30), () -> {
            login("device-web", "web");
            login("device-android", "android");

            Integer activeWeb = jdbcTemplate.queryForObject(
                    "select count(*) from omni.auth_active_sessions "
                            + "where user_id = ? and client_platform = 'web' and revoked_at is null",
                    Integer.class, USER_ID);
            Integer activeAndroid = jdbcTemplate.queryForObject(
                    "select count(*) from omni.auth_active_sessions "
                            + "where user_id = ? and client_platform = 'android' and revoked_at is null",
                    Integer.class, USER_ID);

            assertThat(activeWeb).isEqualTo(1);
            assertThat(activeAndroid).isEqualTo(1);
        });
    }

    private AuthTokenResponse login(String deviceId) {
        return login(deviceId, "web");
    }

    private AuthTokenResponse login(String deviceId, String platform) {
        return authService.login(new LoginRequest(USERNAME, PASSWORD), platform, deviceId,
                deviceId, "127.0.0.1", "JUnit");
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
