package com.omninest.app.auth;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.junit.jupiter.api.Assertions.assertTimeoutPreemptively;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.omninest.OmniNestApplication;
import com.omninest.common.error.BusinessException;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.common.storage.ObjectStorageKey;
import com.omninest.modules.user.service.AuthService;
import java.sql.Timestamp;
import java.time.Duration;
import java.time.Instant;
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
import org.springframework.security.oauth2.jose.jws.MacAlgorithm;
import org.springframework.security.oauth2.jwt.JwsHeader;
import org.springframework.security.oauth2.jwt.JwtClaimsSet;
import org.springframework.security.oauth2.jwt.JwtEncoder;
import org.springframework.security.oauth2.jwt.JwtEncoderParameters;
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
 * 刷新令牌重放的真库回归测试。
 *
 * <p>重放分支必须撤销会话并随当前事务提交：旧实现在持有 {@code PESSIMISTIC_WRITE}
 * 行锁时开 {@code REQUIRES_NEW} 更新同一行，会跨连接自死锁并一直挂住请求。
 * 这里把超时设为硬约束——一旦回退到旧实现，用例以超时失败而不是挂住构建。</p>
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
                "omninest.search.index-path=${java.io.tmpdir}/omninest-auth-replay-it"
        }
)
@ActiveProfiles("dev")
@DirtiesContext(classMode = DirtiesContext.ClassMode.AFTER_CLASS)
@Testcontainers(disabledWithoutDocker = true)
@Import(AuthRefreshReplayIT.ExternalDependencyOverrides.class)
class AuthRefreshReplayIT {

    private static final String POSTGRES_IMAGE = "postgres:18-alpine";
    private static final UUID USER_ID = UUID.fromString("10000000-0000-0000-0000-00000000b001");
    private static final UUID SESSION_ID = UUID.fromString("20000000-0000-0000-0000-00000000b001");

    @Container
    private static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>(POSTGRES_IMAGE)
            .withDatabaseName("omninest_auth_replay_it")
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
    private JwtEncoder jwtEncoder;

    @DynamicPropertySource
    static void registerContainerProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", POSTGRES::getJdbcUrl);
        registry.add("spring.datasource.username", POSTGRES::getUsername);
        registry.add("spring.datasource.password", POSTGRES::getPassword);
        registry.add("spring.data.redis.host", REDIS::getHost);
        registry.add("spring.data.redis.port", () -> REDIS.getMappedPort(6379));
    }

    @BeforeEach
    void seedAccountAndSession() {
        Instant now = Instant.now();
        jdbcTemplate.update("delete from omni.auth_active_sessions where user_id = ?", USER_ID);
        jdbcTemplate.update("delete from omni.auth_session_revocations where user_id = ?", USER_ID);
        jdbcTemplate.update("delete from omni.auth_users where id = ?", USER_ID);
        jdbcTemplate.update(
                "insert into omni.auth_users (id, username, password_hash, status) values (?, ?, ?, 'ACTIVE')",
                USER_ID, "replay-it", "$2a$10$012345678901234567890uGJ0z3q5f7p5z0m9b4Xb3Z0jC6c6b8m2");
        jdbcTemplate.update("""
                insert into omni.auth_active_sessions
                    (id, user_id, client_platform, issued_at, expires_at, last_active_at, created_at,
                     current_refresh_jti)
                values (?, ?, 'web', ?, ?, ?, ?, 'jti-current')
                """,
                SESSION_ID, USER_ID,
                Timestamp.from(now), Timestamp.from(now.plus(Duration.ofDays(30))),
                Timestamp.from(now), Timestamp.from(now));
    }

    @Test
    @DisplayName("刷新令牌重放：立即拒绝且会话撤销状态已提交，不发生在锁内开独立事务的自死锁")
    void replayRevokesSessionWithoutSelfDeadlock() {
        String staleToken = refreshToken("jti-stale");

        assertTimeoutPreemptively(Duration.ofSeconds(15), () ->
                assertThatThrownBy(() -> authService.refresh(staleToken))
                        .isInstanceOf(BusinessException.class)
                        .hasMessageContaining("刷新凭证已失效"));

        Timestamp revokedAt = jdbcTemplate.queryForObject(
                "select revoked_at from omni.auth_active_sessions where id = ?",
                Timestamp.class, SESSION_ID);
        String revokeReason = jdbcTemplate.queryForObject(
                "select revoke_reason from omni.auth_active_sessions where id = ?",
                String.class, SESSION_ID);
        Integer revocationRows = jdbcTemplate.queryForObject(
                "select count(*) from omni.auth_session_revocations where user_id = ? and session_id = ?",
                Integer.class, USER_ID, SESSION_ID);

        assertThat(revokedAt).isNotNull();
        assertThat(revokeReason).contains("刷新令牌重放");
        assertThat(revocationRows).isEqualTo(1);
    }

    private String refreshToken(String jti) {
        Instant now = Instant.now();
        JwtClaimsSet claims = JwtClaimsSet.builder()
                .subject(USER_ID.toString())
                .issuedAt(now)
                .expiresAt(now.plus(Duration.ofMinutes(10)))
                .id(jti)
                .claim("token_use", "refresh")
                .claim("sid", SESSION_ID.toString())
                .build();
        return jwtEncoder
                .encode(JwtEncoderParameters.from(JwsHeader.with(MacAlgorithm.HS256).build(), claims))
                .getTokenValue();
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
