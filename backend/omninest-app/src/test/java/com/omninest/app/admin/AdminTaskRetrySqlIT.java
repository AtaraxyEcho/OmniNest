package com.omninest.app.admin;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.omninest.OmniNestApplication;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.common.storage.ObjectStorageKey;
import com.omninest.modules.user.repository.AdminConsoleMetricsRepository;
import java.util.UUID;
import java.util.function.Supplier;
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
import org.springframework.dao.EmptyResultDataAccessException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.annotation.DirtiesContext;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * 管理员重试任务的原生 SQL 契约测试。
 *
 * <p>该语句依赖 PostgreSQL 的 CTE + RETURNING 与状态守卫；单元测试只桩仓储，
 * 无法证明守卫命中/不命中、{@code completed_at} 置空和终态白名单的真实行为，
 * 因此在真库上执行。</p>
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
                "omninest.search.index-path=${java.io.tmpdir}/omninest-admin-retry-sql-it"
        }
)
@ActiveProfiles("dev")
@Testcontainers(disabledWithoutDocker = true)
@DirtiesContext(classMode = DirtiesContext.ClassMode.AFTER_CLASS)
@Import(AdminTaskRetrySqlIT.ExternalDependencyOverrides.class)
class AdminTaskRetrySqlIT {

    private static final String IMAGE = "postgres:18-alpine";

    @Container
    private static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>(IMAGE)
            .withDatabaseName("omninest_admin_retry_it")
            .withUsername("omninest")
            .withPassword("omninest");

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @Autowired
    private AdminConsoleMetricsRepository metricsRepository;

    @Autowired
    private PlatformTransactionManager transactionManager;

    @DynamicPropertySource
    static void registerDatabaseProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", POSTGRES::getJdbcUrl);
        registry.add("spring.datasource.username", POSTGRES::getUsername);
        registry.add("spring.datasource.password", POSTGRES::getPassword);
    }

    @Test
    @DisplayName("管理员重试清除完成时间与心跳并复位重试阶梯")
    void retryClearsCompletionHeartbeatAndRetryLadder() {
        UUID taskId = insertTask("FAILED");

        var retried = inTransaction(() ->
                metricsRepository.updateTaskStatusReturning(taskId, "QUEUED", 0));

        assertThat(retried.status()).isEqualTo("QUEUED");
        assertThat(retried.retryCount()).isZero();
        assertThat(retried.progress()).isZero();
        assertThat(retried.errorSummary()).isNull();
        assertThat(column(taskId, "completed_at")).isNull();
        assertThat(column(taskId, "heartbeat_at")).isNull();
        assertThat(column(taskId, "stack_summary")).isNull();
        assertThat(column(taskId, "next_retry_at")).isNull();
    }

    @Test
    @DisplayName("非终态任务不符合重试守卫，SQL 不返回行")
    void retryRejectsTaskThatIsAlreadyRunning() {
        UUID taskId = insertTask("RUNNING");

        // 仓储的异常翻译会把 NoResultException 转成 EmptyResultDataAccessException；
        // 服务层两种类型都捕获，否则运行时返回 500 而不是稳定业务错误。
        assertThatThrownBy(() -> inTransaction(() ->
                metricsRepository.updateTaskStatusReturning(taskId, "QUEUED", 0)))
                .isInstanceOf(EmptyResultDataAccessException.class);
        assertThat(column(taskId, "status")).isEqualTo("RUNNING");
        assertThat(column(taskId, "completed_at")).isNotNull();
    }

    @Test
    @DisplayName("已复位为 QUEUED 的任务不能被再次重试覆盖")
    void retryGuardRejectsSecondAttempt() {
        UUID taskId = insertTask("FAILED");
        inTransaction(() -> metricsRepository.updateTaskStatusReturning(taskId, "QUEUED", 0));

        assertThatThrownBy(() -> inTransaction(() ->
                metricsRepository.updateTaskStatusReturning(taskId, "QUEUED", 0)))
                .isInstanceOf(EmptyResultDataAccessException.class);
    }

    @Test
    @DisplayName("取消与死信任务同样允许重试")
    void cancelledAndDlqTasksAreRetryable() {
        UUID cancelled = insertTask("CANCELLED");
        UUID deadLetter = insertTask("DLQ");

        assertThat(inTransaction(() ->
                metricsRepository.updateTaskStatusReturning(cancelled, "QUEUED", 0)).status())
                .isEqualTo("QUEUED");
        assertThat(inTransaction(() ->
                metricsRepository.updateTaskStatusReturning(deadLetter, "QUEUED", 0)).status())
                .isEqualTo("QUEUED");
    }

    private UUID insertTask(String status) {
        UUID taskId = UUID.randomUUID();
        jdbcTemplate.update("""
                insert into omni.sys_tasks (
                    id, task_type, status, routing_key, progress, retry_count,
                    error_summary, stack_summary, created_at, updated_at,
                    completed_at, heartbeat_at, next_retry_at
                ) values (?, 'FILE_INDEX', ?, 'file.index', 40, 3,
                          'boom', 'stack', now(), now(),
                          case when ? in ('RUNNING', 'COMPLETED', 'FAILED', 'CANCELLED', 'DLQ')
                               then now() else null end,
                          now(), now())
                """, taskId, status, status);
        return taskId;
    }

    private Object column(UUID taskId, String column) {
        return jdbcTemplate.queryForObject(
                "select " + column + " from omni.sys_tasks where id = ?",
                Object.class,
                taskId
        );
    }

    private <T> T inTransaction(Supplier<T> action) {
        TransactionTemplate template = new TransactionTemplate(transactionManager);
        return template.execute(status -> action.get());
    }

    /**
     * 外部依赖替身：本用例只验证 SQL 契约，不需要对象存储与 RabbitMQ。
     */
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
