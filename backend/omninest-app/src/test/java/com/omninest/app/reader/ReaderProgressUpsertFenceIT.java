package com.omninest.app.reader;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.omninest.OmniNestApplication;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.common.storage.ObjectStorageKey;
import com.omninest.modules.reader.repository.ReaderProgressRepository;
import java.math.BigDecimal;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
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
import org.springframework.transaction.annotation.Transactional;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * 阅读进度写入围栏的真库集成测试。
 *
 * <p>围栏写在 {@code ON CONFLICT ... DO UPDATE ... WHERE} 上，属于原生 SQL 条件，
 * 单元测试的 Mock 只能验证调用参数，无法证明数据库真的拒绝过早上报。本测试在真实
 * PostgreSQL 上按线上写入路径连续上报，验证"新覆盖旧、旧不覆盖新、缺时间戳放行"。
 *
 * <p>直接调用仓储而非服务：仓储的 {@code @Modifying} 需要活动事务，测试事务同时
 * 提供事务与用例间隔离；服务侧行为（所有权校验、同步事件）由单元测试覆盖。
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
                "omninest.search.index-path=${java.io.tmpdir}/omninest-reader-progress-it"
        }
)
@ActiveProfiles("dev")
@Testcontainers(disabledWithoutDocker = true)
@Transactional
@Import(ReaderProgressUpsertFenceIT.ExternalDependencyOverrides.class)
class ReaderProgressUpsertFenceIT {

    private static final String IMAGE = "postgres:18-alpine";

    @Container
    private static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>(IMAGE)
            .withDatabaseName("omninest_reader_progress_it")
            .withUsername("omninest")
            .withPassword("omninest");

    @Autowired
    private ReaderProgressRepository progressRepository;

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @DynamicPropertySource
    static void registerDatabaseProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", POSTGRES::getJdbcUrl);
        registry.add("spring.datasource.username", POSTGRES::getUsername);
        registry.add("spring.datasource.password", POSTGRES::getPassword);
    }

    @Test
    @DisplayName("更新的上报覆盖旧位置，更早的上报被拒绝")
    void newerReportWinsAndStaleReportIsIgnored() {
        UUID owner = UUID.randomUUID();
        UUID item = UUID.randomUUID();
        Instant early = Instant.now().minus(20, ChronoUnit.MINUTES);
        Instant late = Instant.now().minus(5, ChronoUnit.MINUTES);

        assertThat(upsert(owner, item, 1_000, early)).isEqualTo(1);
        assertThat(upsert(owner, item, 9_000, late)).isEqualTo(1);
        assertThat(readCharOffset(owner, item)).isEqualTo(9_000L);

        // 离线排队的旧上报：晚到达但记录时刻更早，不得改写已同步的位置。
        assertThat(upsert(owner, item, 2_000, early)).isEqualTo(0);
        assertThat(readCharOffset(owner, item)).isEqualTo(9_000L);
    }

    @Test
    @DisplayName("已存记录缺少上报时间时放行首次写入")
    void missingStoredStampStillAcceptsWrite() {
        UUID owner = UUID.randomUUID();
        UUID item = UUID.randomUUID();
        jdbcTemplate.update("""
                INSERT INTO omni.reader_progress
                    (id, owner_user_id, reader_item_id, char_offset, progress_percent,
                     reading_mode, chapter_id, created_at, updated_at, version)
                VALUES (?, ?, ?, 400, 0.1, 'scroll', '', now(), now(), 1)
                """, UUID.randomUUID(), owner, item);

        assertThat(upsert(owner, item, 800, Instant.now().minus(1, ChronoUnit.HOURS))).isEqualTo(1);
        assertThat(readCharOffset(owner, item)).isEqualTo(800L);
    }

    private int upsert(UUID owner, UUID item, long charOffset, Instant reportedAt) {
        return progressRepository.upsertProgress(
                owner,
                item,
                charOffset,
                BigDecimal.valueOf(0.5),
                "scroll",
                "chapter-1",
                null,
                null,
                null,
                null,
                null,
                null,
                1,
                null,
                reportedAt);
    }

    private long readCharOffset(UUID owner, UUID item) {
        Long value = jdbcTemplate.queryForObject(
                "SELECT char_offset FROM omni.reader_progress WHERE owner_user_id = ? AND reader_item_id = ?",
                Long.class,
                owner,
                item);
        return value == null ? -1L : value;
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
