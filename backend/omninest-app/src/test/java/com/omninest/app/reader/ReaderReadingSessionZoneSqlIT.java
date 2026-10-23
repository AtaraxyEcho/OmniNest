package com.omninest.app.reader;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.tuple;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.omninest.OmniNestApplication;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.common.storage.ObjectStorageKey;
import com.omninest.modules.reader.repository.ReaderReadingSessionRepository;
import java.sql.Timestamp;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
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
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * 阅读统计时区原生 SQL 的真库集成测试。
 *
 * <p>统计口径从"固定偏移 INTERVAL"改成"AT TIME ZONE 区名"，只有真实 PostgreSQL 能证明
 * 三件事：区名为 UTC 时语句可执行（旧写法在 JVM 时区为 UTC 时因 {@code CAST('Z' AS INTERVAL)}
 * 直接报语法错误）、同一时刻在不同区名下归档到不同本地日、跨夏令时切换日的时刻按本地日聚合。
 * 单元测试只 Mock 仓储，上下文冒烟只解析不执行原生 SQL，两者都证不到这些。</p>
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
                "omninest.search.index-path=${java.io.tmpdir}/omninest-reader-zone-it"
        }
)
@ActiveProfiles("dev")
@Testcontainers(disabledWithoutDocker = true)
@Import(ReaderReadingSessionZoneSqlIT.ExternalDependencyOverrides.class)
class ReaderReadingSessionZoneSqlIT {

    private static final String IMAGE = "postgres:18-alpine";

    @Container
    private static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>(IMAGE)
            .withDatabaseName("omninest_reader_zone_it")
            .withUsername("omninest")
            .withPassword("omninest");

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @Autowired
    private ReaderReadingSessionRepository sessionRepository;

    @DynamicPropertySource
    static void registerDatabaseProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", POSTGRES::getJdbcUrl);
        registry.add("spring.datasource.username", POSTGRES::getUsername);
        registry.add("spring.datasource.password", POSTGRES::getPassword);
    }

    @Test
    @DisplayName("UTC 区名可执行，且同一时刻按区名归档到不同本地日")
    void zoneNamesResolveLocalDaysInsteadOfFixedOffset() {
        UUID owner = UUID.randomUUID();
        UUID item = UUID.randomUUID();
        // 2026-10-04T20:00Z：UTC 本地日是 10-04，Asia/Shanghai 已是 10-05 凌晨。
        Instant moment = Instant.parse("2026-10-04T20:00:00Z");
        insertSession(owner, item, moment, 600);

        assertThat(sessionRepository.distinctReadingDaysSince(
                owner, Instant.parse("2026-10-01T00:00:00Z"), "UTC"))
                .containsExactly(LocalDate.of(2026, 10, 4));
        assertThat(sessionRepository.distinctReadingDaysSince(
                owner, Instant.parse("2026-10-01T00:00:00Z"), "Asia/Shanghai"))
                .containsExactly(LocalDate.of(2026, 10, 5));

        assertThat(sessionRepository.sumDailyMinutesSince(
                owner, Instant.parse("2026-10-01T00:00:00Z"), "UTC"))
                .singleElement()
                .satisfies(row -> {
                    assertThat(row.getDay()).isEqualTo(LocalDate.of(2026, 10, 4));
                    assertThat(row.getMinutes()).isEqualTo(10L);
                });
        assertThat(sessionRepository.sumDailyMinutesSince(
                owner, Instant.parse("2026-10-01T00:00:00Z"), "Asia/Shanghai"))
                .singleElement()
                .satisfies(row -> assertThat(row.getDay()).isEqualTo(LocalDate.of(2026, 10, 5)));
    }

    @Test
    @DisplayName("跨夏令时切换日的时刻按本地日聚合，不受固定偏移影响")
    void daylightSavingSwitchBucketsByLocalDay() {
        UUID owner = UUID.randomUUID();
        UUID item = UUID.randomUUID();
        // 美东 2026-03-08 02:00 拨到 03:00：2026-03-08T06:00Z 是当地 01:00（EST），
        // 2026-03-08T05:00Z 之前一小时是当地 00:00，同一 UTC 日内本地日仍按切换后口径归档。
        insertSession(owner, item, Instant.parse("2026-03-08T06:30:00Z"), 300);
        insertSession(owner, item, Instant.parse("2026-03-09T10:30:00Z"), 900);

        List<LocalDate> days = sessionRepository.distinctReadingDaysSince(
                owner, Instant.parse("2026-03-01T00:00:00Z"), "America/New_York");

        assertThat(days).containsExactly(LocalDate.of(2026, 3, 9), LocalDate.of(2026, 3, 8));
        assertThat(sessionRepository.sumDailyMinutesSince(
                owner, Instant.parse("2026-03-01T00:00:00Z"), "America/New_York"))
                .extracting(
                        ReaderReadingSessionRepository.DailyMinutesView::getDay,
                        ReaderReadingSessionRepository.DailyMinutesView::getMinutes)
                .containsExactly(
                        tuple(LocalDate.of(2026, 3, 8), 5L),
                        tuple(LocalDate.of(2026, 3, 9), 15L));
    }

    private void insertSession(UUID ownerUserId, UUID readerItemId, Instant startedAt, int durationSeconds) {
        jdbcTemplate.update("""
                INSERT INTO omni.reader_reading_sessions
                    (owner_user_id, reader_item_id, started_at, ended_at, duration_seconds, created_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                ownerUserId,
                readerItemId,
                Timestamp.from(startedAt),
                Timestamp.from(startedAt.plusSeconds(durationSeconds)),
                durationSeconds,
                Timestamp.from(startedAt));
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
