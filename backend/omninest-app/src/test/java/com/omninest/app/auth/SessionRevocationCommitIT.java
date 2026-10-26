package com.omninest.app.auth;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.omninest.OmniNestApplication;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.common.storage.ObjectStorageKey;
import com.omninest.modules.user.service.SessionRevocationWriter;
import java.sql.Timestamp;
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
import org.springframework.test.annotation.DirtiesContext;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.transaction.support.TransactionTemplate;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * 会话吊销独立提交的真库集成测试。
 *
 * <p>C-01 的关键不是“写了撤销”，而是“外层因重放拒绝回滚后撤销仍在”。这里在一个
 * 人为抛错的外层事务里调用吊销写入，断言数据库里的撤销记录与会话状态都已提交；
 * 若把 writer 的传播行为退回 REQUIRED，两条断言都会失败。</p>
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
                "omninest.search.index-path=${java.io.tmpdir}/omninest-revocation-it"
        }
)
@ActiveProfiles("dev")
@DirtiesContext(classMode = DirtiesContext.ClassMode.AFTER_CLASS)
@Testcontainers(disabledWithoutDocker = true)
@Import(SessionRevocationCommitIT.ExternalDependencyOverrides.class)
class SessionRevocationCommitIT {

    private static final String IMAGE = "postgres:18-alpine";

    @Container
    private static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>(IMAGE)
            .withDatabaseName("omninest_revocation_it")
            .withUsername("omninest")
            .withPassword("omninest");

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @Autowired
    private SessionRevocationWriter writer;

    @Autowired
    private TransactionTemplate transactionTemplate;

    @DynamicPropertySource
    static void registerDatabaseProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", POSTGRES::getJdbcUrl);
        registry.add("spring.datasource.username", POSTGRES::getUsername);
        registry.add("spring.datasource.password", POSTGRES::getPassword);
    }

    @Test
    @DisplayName("外层事务回滚时撤销记录与会话撤销状态仍已提交")
    void revocationSurvivesOuterRollback() {
        UUID userId = UUID.randomUUID();
        UUID sessionId = UUID.randomUUID();
        seedSession(userId, sessionId);

        assertThatThrownBy(() -> transactionTemplate.executeWithoutResult(status -> {
            writer.persistRevocationAndDeactivate(userId, sessionId, "刷新令牌重放，会话已撤销");
            throw new IllegalStateException("刷新请求最终被拒绝");
        })).isInstanceOf(IllegalStateException.class);

        Integer revocationRows = jdbcTemplate.queryForObject(
                "select count(*) from omni.auth_session_revocations where user_id = ? and session_id = ?",
                Integer.class, userId, sessionId);
        String revokeReason = jdbcTemplate.queryForObject(
                "select revoke_reason from omni.auth_active_sessions where id = ?",
                String.class, sessionId);
        Timestamp revokedAt = jdbcTemplate.queryForObject(
                "select revoked_at from omni.auth_active_sessions where id = ?",
                Timestamp.class, sessionId);

        assertThat(revocationRows).isEqualTo(1);
        assertThat(revokeReason).isEqualTo("刷新令牌重放，会话已撤销");
        assertThat(revokedAt).isNotNull();
    }

    private void seedSession(UUID userId, UUID sessionId) {
        Instant now = Instant.now();
        jdbcTemplate.update("""
                INSERT INTO omni.auth_active_sessions
                    (id, user_id, client_platform, issued_at, expires_at, last_active_at, created_at)
                VALUES (?, ?, 'WEB', ?, ?, ?, ?)
                """,
                sessionId,
                userId,
                Timestamp.from(now),
                Timestamp.from(now.plusSeconds(3600)),
                Timestamp.from(now),
                Timestamp.from(now));
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
