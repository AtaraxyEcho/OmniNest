package com.omninest.app.music;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.omninest.OmniNestApplication;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.common.storage.ObjectStorageKey;
import com.omninest.modules.music.service.MusicCoverReconciliationService;
import com.omninest.modules.music.service.MusicCoverRetentionService;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.sql.Timestamp;
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
 * 音乐封面资产回收的真库集成测试。
 *
 * <p>回收与对账的判据全部落在真实 SQL 上：派生节点按 {@code normalized_path} 前缀筛出、
 * 四张业务表决定封面是否存活、删除要求 {@code source_type=DERIVED} 且未软删。单元测试用
 * Mock 覆盖不到这些条件，本测试在真实 PostgreSQL 上按线上实际路径形态建数据并验证结果。</p>
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
                "omninest.search.index-path=${java.io.tmpdir}/omninest-music-cover-it"
        }
)
@ActiveProfiles("dev")
@Testcontainers(disabledWithoutDocker = true)
@Import(MusicCoverAssetRecoveryIT.ExternalDependencyOverrides.class)
class MusicCoverAssetRecoveryIT {

    private static final String IMAGE = "postgres:18-alpine";
    private static final Instant OLD = Instant.now().minus(30, ChronoUnit.MINUTES);

    @Container
    private static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>(IMAGE)
            .withDatabaseName("omninest_music_cover_it")
            .withUsername("omninest")
            .withPassword("omninest");

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @Autowired
    private MusicCoverReconciliationService reconciliationService;

    @Autowired
    private MusicCoverRetentionService retentionService;

    @DynamicPropertySource
    static void registerDatabaseProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", POSTGRES::getJdbcUrl);
        registry.add("spring.datasource.username", POSTGRES::getUsername);
        registry.add("spring.datasource.password", POSTGRES::getPassword);
    }

    @Test
    @DisplayName("对账删除源封面已失效的缩略图，保留在用封面与其缩略图")
    void reconciliationRemovesOnlyOrphanThumbnails() {
        UUID owner = UUID.randomUUID();
        UUID audioNode = insertNode(owner, "/Music/it-" + UUID.randomUUID() + ".mp3", "audio/mpeg", "LOCAL", OLD);
        UUID liveCover = insertDerivedNode(owner,
                "/.metadata/MUSIC_COVER/" + audioNode + "/COVER/cover.jpg", OLD);
        insertDerivedNode(owner,
                "/.metadata/MUSIC_COVER/" + liveCover + "/THUMBNAIL/cover_300.jpg", OLD);
        UUID orphanThumbnail = insertDerivedNode(owner,
                "/.metadata/MUSIC_COVER/" + UUID.randomUUID() + "/THUMBNAIL/cover_300.jpg", OLD);
        insertTrack(owner, audioNode, liveCover);

        reconciliationService.reconcile();

        assertThat(nodeExists(liveCover)).isTrue();
        assertThat(nodeExists(orphanThumbnail)).isFalse();
        assertThat(liveCoverThumbnailExists(owner, liveCover)).isTrue();
    }

    @Test
    @DisplayName("宽限期内的无主封面保留，避免删掉正在写引用的节点")
    void reconciliationKeepsNodesInsideTheGraceWindow() {
        UUID owner = UUID.randomUUID();
        UUID freshCover = insertDerivedNode(owner,
                "/.metadata/MUSIC_COVER/" + UUID.randomUUID() + "/COVER/cover.jpg", Instant.now());

        reconciliationService.reconcile();

        assertThat(nodeExists(freshCover)).isTrue();
    }

    @Test
    @DisplayName("超过宽限期且无人引用的封面本体由对账回收")
    void reconciliationReclaimsAgedUnreferencedCover() {
        UUID owner = UUID.randomUUID();
        UUID abandonedCover = insertDerivedNode(owner,
                "/.metadata/MUSIC_COVER/" + UUID.randomUUID() + "/COVER/cover.jpg", OLD);

        reconciliationService.reconcile();

        assertThat(nodeExists(abandonedCover)).isFalse();
    }

    @Test
    @DisplayName("曲目删除后释放封面时，封面与缩略图一起消失")
    void releaseRemovesCoverAndThumbnailTogether() {
        UUID owner = UUID.randomUUID();
        UUID audioNode = insertNode(owner, "/Music/it-" + UUID.randomUUID() + ".mp3", "audio/mpeg", "LOCAL", OLD);
        UUID cover = insertDerivedNode(owner,
                "/.metadata/MUSIC_COVER/" + audioNode + "/COVER/cover.jpg", OLD);
        UUID thumbnail = insertDerivedNode(owner,
                "/.metadata/MUSIC_COVER/" + cover + "/THUMBNAIL/cover_300.jpg", OLD);
        UUID trackId = insertTrack(owner, audioNode, cover);

        jdbcTemplate.update("DELETE FROM omni.music_tracks WHERE id = ?", trackId);
        retentionService.releaseUnreferenced(owner, cover);

        assertThat(nodeExists(cover)).isFalse();
        assertThat(nodeExists(thumbnail)).isFalse();
    }

    @Test
    @DisplayName("封面被另一曲目共用时，单行释放不得删除它")
    void releaseKeepsSharedCover() {
        UUID owner = UUID.randomUUID();
        UUID audioNode = insertNode(owner, "/Music/it-" + UUID.randomUUID() + ".mp3", "audio/mpeg", "LOCAL", OLD);
        UUID sharedAudioNode = insertNode(owner,
                "/Music/it-shared-" + UUID.randomUUID() + ".mp3", "audio/mpeg", "LOCAL", OLD);
        UUID cover = insertDerivedNode(owner,
                "/.metadata/MUSIC_COVER/" + audioNode + "/COVER/cover.jpg", OLD);
        UUID removedTrack = insertTrack(owner, audioNode, cover);
        insertTrack(owner, sharedAudioNode, cover);

        jdbcTemplate.update("DELETE FROM omni.music_tracks WHERE id = ?", removedTrack);
        retentionService.releaseUnreferenced(owner, cover);

        assertThat(nodeExists(cover)).isTrue();
    }

    private UUID insertNode(
            UUID ownerUserId,
            String normalizedPath,
            String mimeType,
            String sourceType,
            Instant createdAt
    ) {
        UUID nodeId = UUID.randomUUID();
        UUID objectId = insertObject(normalizedPath);
        jdbcTemplate.update("""
                INSERT INTO omni.file_nodes
                    (id, owner_user_id, node_type, name, normalized_path, mime_type, size_bytes,
                     current_object_id, source_type, created_at, updated_at, version, space_type)
                VALUES (?, ?, 'FILE', ?, ?, ?, 2048, ?, ?, ?, ?, 0, 'PERSONAL')
                """, nodeId, ownerUserId, fileNameOf(normalizedPath), normalizedPath, mimeType,
                objectId, sourceType, Timestamp.from(createdAt), Timestamp.from(createdAt));
        return nodeId;
    }

    private UUID insertDerivedNode(UUID ownerUserId, String normalizedPath, Instant createdAt) {
        return insertNode(ownerUserId, normalizedPath, "image/jpeg", "DERIVED", createdAt);
    }

    private UUID insertObject(String relatedPath) {
        UUID objectId = UUID.randomUUID();
        jdbcTemplate.update("""
                INSERT INTO omni.file_objects (id, bucket_name, object_key, size_bytes, created_at)
                VALUES (?, 'omninest-derived', ?, 2048, now())
                """, objectId, "music/" + relatedPath + "#" + objectId);
        return objectId;
    }

    private UUID insertTrack(UUID ownerUserId, UUID fileNodeId, UUID coverFileId) {
        UUID trackId = UUID.randomUUID();
        jdbcTemplate.update("""
                INSERT INTO omni.music_tracks
                    (id, owner_user_id, file_node_id, title, cover_file_id, created_at, updated_at, version)
                VALUES (?, ?, ?, 'IT Track', ?, now(), now(), 0)
                """, trackId, ownerUserId, fileNodeId, coverFileId);
        return trackId;
    }

    private boolean nodeExists(UUID nodeId) {
        Integer count = jdbcTemplate.queryForObject(
                "SELECT count(*) FROM omni.file_nodes WHERE id = ?", Integer.class, nodeId);
        return count != null && count > 0;
    }

    private boolean liveCoverThumbnailExists(UUID ownerUserId, UUID coverFileId) {
        Integer count = jdbcTemplate.queryForObject("""
                SELECT count(*) FROM omni.file_nodes
                WHERE owner_user_id = ? AND source_type = 'DERIVED' AND is_deleted = false
                  AND normalized_path = ?
                """, Integer.class, ownerUserId,
                "/.metadata/MUSIC_COVER/" + coverFileId + "/THUMBNAIL/cover_300.jpg");
        return count != null && count > 0;
    }

    private String fileNameOf(String normalizedPath) {
        int index = normalizedPath.lastIndexOf('/');
        return index >= 0 ? normalizedPath.substring(index + 1) : normalizedPath;
    }

    /**
     * 外部基础设施替换为测试边界：对象存储与 AMQP 管理不需要真实实例，
     * 监听容器不得启动，但删除路径要跑真实的元数据操作。
     */
    @TestConfiguration(proxyBeanMethods = false)
    static class ExternalDependencyOverrides {

        @Bean
        @Primary
        ObjectStorageClient objectStorageClient() {
            ObjectStorageClient client = mock(ObjectStorageClient.class);
            // 派生资产只有在物理对象存在时才算可用；种子数据已建好 file_objects，
            // 这里把存在性判定固定为真，否则回收会看不见待删节点。
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
