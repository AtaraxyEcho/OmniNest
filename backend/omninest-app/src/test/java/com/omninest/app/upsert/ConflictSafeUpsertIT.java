package com.omninest.app.upsert;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.omninest.OmniNestApplication;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.common.storage.ObjectStorageKey;
import com.omninest.modules.user.repository.AuthTotpCredentialRepository;
import com.omninest.modules.video.repository.ContentAssetRepository;
import com.omninest.modules.video.repository.MediaWatchHistoryRepository;
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
import org.springframework.test.annotation.DirtiesContext;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.transaction.annotation.Transactional;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * 幂等写入围栏的真库集成测试。
 *
 * <p>观看历史、主资产与 TOTP 秘钥三处都改成 {@code INSERT ... ON CONFLICT DO UPDATE}，
 * 冲突条件与部分唯一索引谓词都写在原生 SQL 里：Mock 仓储的单元测试只能证明调用参数，
 * 证明不了「同一目标第二次写入不会插出第二行」，也证明不了索引谓词写得对。
 * 本测试在真实 PostgreSQL 上逐个重复写入并按行数收口。</p>
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
                "omninest.search.index-path=${java.io.tmpdir}/omninest-upsert-fence-it"
        }
)
@ActiveProfiles("dev")
@DirtiesContext(classMode = DirtiesContext.ClassMode.AFTER_CLASS)
@Testcontainers(disabledWithoutDocker = true)
@Transactional
@Import(ConflictSafeUpsertIT.ExternalDependencyOverrides.class)
class ConflictSafeUpsertIT {

    private static final String IMAGE = "postgres:18-alpine";

    @Container
    private static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>(IMAGE)
            .withDatabaseName("omninest_upsert_fence_it")
            .withUsername("omninest")
            .withPassword("omninest");

    @Autowired
    private MediaWatchHistoryRepository watchHistoryRepository;

    @Autowired
    private ContentAssetRepository contentAssetRepository;

    @Autowired
    private AuthTotpCredentialRepository totpCredentialRepository;

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @DynamicPropertySource
    static void registerDatabaseProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", POSTGRES::getJdbcUrl);
        registry.add("spring.datasource.username", POSTGRES::getUsername);
        registry.add("spring.datasource.password", POSTGRES::getPassword);
    }

    @Test
    @DisplayName("同一视频的并发上报只留一行观看历史")
    void watchHistoryUpsertKeepsOneRowPerVideo() {
        UUID owner = UUID.randomUUID();
        UUID videoItem = UUID.randomUUID();
        Instant earlier = Instant.now().minus(10, ChronoUnit.MINUTES);
        Instant later = Instant.now();

        assertThat(upsertHistory(owner, videoItem, 120, earlier)).isEqualTo(1);
        assertThat(upsertHistory(owner, videoItem, 640, later)).isEqualTo(1);

        assertThat(count("SELECT count(*) FROM omni.media_watch_history"
                + " WHERE owner_user_id = ? AND video_item_id = ?", owner, videoItem)).isEqualTo(1);
        assertThat(jdbcTemplate.queryForObject("""
                SELECT position_seconds FROM omni.media_watch_history
                WHERE owner_user_id = ? AND video_item_id = ?
                """, Long.class, owner, videoItem)).isEqualTo(640L);
    }

    @Test
    @DisplayName("同一资源的主资产重复写入不撞部分唯一索引")
    void primaryAssetUpsertSurvivesConcurrentScrape() {
        UUID owner = UUID.randomUUID();
        UUID movieId = UUID.randomUUID();
        UUID firstPoster = UUID.randomUUID();
        UUID secondPoster = UUID.randomUUID();

        assertThat(upsertAsset(owner, movieId, firstPoster, "https://cdn/1.jpg", "{\"v\":1}")).isEqualTo(1);
        assertThat(upsertAsset(owner, movieId, secondPoster, "https://cdn/2.jpg", "{\"v\":2}")).isEqualTo(1);

        assertThat(count("SELECT count(*) FROM omni.content_assets"
                + " WHERE resource_type = 'MOVIE' AND resource_id = ? AND is_primary", movieId)).isEqualTo(1);
        assertThat(jdbcTemplate.queryForObject("""
                SELECT file_node_id FROM omni.content_assets
                WHERE resource_type = 'MOVIE' AND resource_id = ? AND asset_type = 'POSTER' AND is_primary
                """, UUID.class, movieId)).isEqualTo(secondPoster);
        assertThat(versionOf("content_assets", "resource_id = ? AND asset_type = 'POSTER'", movieId))
                .isGreaterThanOrEqualTo(1L);
    }

    @Test
    @DisplayName("重复发起两步验证绑定只留一行凭据并覆盖秘钥")
    void totpSecretStagingKeepsOneRowPerUser() {
        UUID owner = UUID.randomUUID();
        String firstSecret = "v1:" + UUID.randomUUID();
        String secondSecret = "v2:" + UUID.randomUUID();

        assertThat(totpCredentialRepository.stageSecret(owner, firstSecret, Instant.now())).isEqualTo(1);
        assertThat(totpCredentialRepository.stageSecret(owner, secondSecret, Instant.now())).isEqualTo(1);

        assertThat(count("SELECT count(*) FROM omni.auth_totp_credentials WHERE user_id = ?", owner)).isEqualTo(1);
        assertThat(jdbcTemplate.queryForObject(
                "SELECT secret FROM omni.auth_totp_credentials WHERE user_id = ?", String.class, owner))
                .isEqualTo(secondSecret);
    }

    private int upsertHistory(UUID owner, UUID videoItem, long position, Instant playedAt) {
        return watchHistoryRepository.upsertWatched(
                UUID.randomUUID(), owner, videoItem, position, 1_800L, false, playedAt);
    }

    private int upsertAsset(UUID owner, UUID movieId, UUID fileNodeId, String url, String metadataJson) {
        return contentAssetRepository.upsertPrimary(
                UUID.randomUUID(), owner, "MOVIE", movieId, "POSTER", fileNodeId,
                url, "TMDB", 0, metadataJson, Instant.now());
    }

    private int count(String sql, Object... args) {
        Integer value = jdbcTemplate.queryForObject(sql, Integer.class, args);
        return value == null ? 0 : value;
    }

    private long versionOf(String table, String where, Object arg) {
        Long value = jdbcTemplate.queryForObject(
                "SELECT version FROM omni." + table + " WHERE " + where, Long.class, arg);
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
