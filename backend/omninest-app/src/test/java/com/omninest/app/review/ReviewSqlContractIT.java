package com.omninest.app.review;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.omninest.OmniNestApplication;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.common.storage.ObjectStorageKey;
import com.omninest.modules.music.domain.MusicPlaylistItem;
import com.omninest.modules.music.repository.MusicPlaylistItemRepository;
import com.omninest.modules.photos.repository.PhotoGroupPreviewProjection;
import com.omninest.modules.photos.repository.PhotoItemRepository;
import com.omninest.modules.photos.repository.PhotoRelationEdgeProjection;
import com.omninest.modules.photos.repository.PhotoRelationNodeProjection;
import com.omninest.modules.sync.domain.SyncEvent;
import com.omninest.modules.sync.repository.SyncEventRepository;
import com.omninest.modules.task.domain.TaskDispatch;
import com.omninest.modules.task.repository.TaskDispatchRepository;
import java.sql.Timestamp;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Map;
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
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * 本轮修复涉及的原生 SQL 契约测试。
 *
 * <p>关系图谱、日期分组、Outbox 显式列与歌单分页都依赖真实 PostgreSQL 的
 * JSONB、时区转换、FOR UPDATE SKIP LOCKED 和生成列；单元测试只桩仓储，
 * 上下文冒烟也只解析查询而不执行，因此必须在这里跑真库。</p>
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
                "omninest.search.index-path=${java.io.tmpdir}/omninest-review-sql-it"
        }
)
@ActiveProfiles("dev")
@Testcontainers(disabledWithoutDocker = true)
@Import(ReviewSqlContractIT.ExternalDependencyOverrides.class)
class ReviewSqlContractIT {

    private static final String IMAGE = "postgres:18-alpine";
    private static final String ZONE_ID = "UTC";

    @Container
    private static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>(IMAGE)
            .withDatabaseName("omninest_review_sql_it")
            .withUsername("omninest")
            .withPassword("omninest");

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @Autowired
    private PhotoItemRepository photoItemRepository;

    @Autowired
    private SyncEventRepository syncEventRepository;

    @Autowired
    private TaskDispatchRepository taskDispatchRepository;

    @Autowired
    private MusicPlaylistItemRepository playlistItemRepository;

    @Autowired
    private PlatformTransactionManager transactionManager;

    @DynamicPropertySource
    static void registerDatabaseProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", POSTGRES::getJdbcUrl);
        registry.add("spring.datasource.username", POSTGRES::getUsername);
        registry.add("spring.datasource.password", POSTGRES::getPassword);
    }

    @Test
    @DisplayName("照片关系图谱六条查询都排除底层文件已删除的照片")
    void relationQueriesExcludeFileDeletedPhotos() {
        UUID owner = UUID.randomUUID();
        UUID albumA = insertAlbum(owner, "A");
        UUID albumB = insertAlbum(owner, "B");
        UUID activePhoto = insertPhoto(owner, false, instant("2026-01-10"), instant("2026-01-20"), "Shanghai");
        UUID fileDeletedPhoto = insertPhoto(owner, true, instant("2026-01-15"), instant("2026-01-21"), "Shanghai");
        addToAlbum(owner, albumA, activePhoto);
        addToAlbum(owner, albumB, activePhoto);
        addToAlbum(owner, albumA, fileDeletedPhoto);
        addToAlbum(owner, albumB, fileDeletedPhoto);

        UUID lowerAlbum = albumA.compareTo(albumB) < 0 ? albumA : albumB;
        UUID higherAlbum = albumA.compareTo(albumB) < 0 ? albumB : albumA;
        assertThat(photoItemRepository.findAlbumAlbumRelationEdges(owner, 20))
                .singleElement()
                .satisfies(edge -> {
                    assertThat(edge.getSourceKey()).isEqualTo(lowerAlbum.toString());
                    assertThat(edge.getTargetKey()).isEqualTo(higherAlbum.toString());
                    assertThat(edge.getWeight()).isEqualTo(1L);
                });
        assertThat(photoItemRepository.findAlbumTimeRelationEdges(owner, ZONE_ID, 20))
                .hasSize(2)
                .allSatisfy(edge -> assertThat(edge.getWeight()).isEqualTo(1L));
        assertThat(photoItemRepository.findAlbumLocationRelationEdges(owner, 20))
                .hasSize(2)
                .allSatisfy(edge -> {
                    assertThat(edge.getTargetKey()).isEqualTo("Shanghai");
                    assertThat(edge.getWeight()).isEqualTo(1L);
                });
        assertThat(photoItemRepository.findTimeLocationRelationEdges(owner, ZONE_ID, 20))
                .singleElement()
                .satisfies(edge -> {
                    assertThat(edge.getSourceKey()).isEqualTo("2026-01");
                    assertThat(edge.getTargetKey()).isEqualTo("Shanghai");
                    assertThat(edge.getWeight()).isEqualTo(1L);
                });
        assertThat(photoItemRepository.findTimeRelationNodes(owner, ZONE_ID, 20))
                .singleElement()
                .satisfies(node -> {
                    assertThat(node.getKey()).isEqualTo("2026-01");
                    assertThat(node.getWeight()).isEqualTo(1L);
                });
        assertThat(photoItemRepository.findLocationRelationNodes(owner, 20))
                .singleElement()
                .satisfies(node -> {
                    assertThat(node.getKey()).isEqualTo("Shanghai");
                    assertThat(node.getWeight()).isEqualTo(1L);
                });
    }

    @Test
    @DisplayName("日期分组把无 EXIF 照片按创建时间归档，并按有效时间排序预览")
    void dateGroupPreviewUsesCreatedAtFallbackAndEffectiveOrder() {
        UUID owner = UUID.randomUUID();
        UUID exifPhoto = insertPhoto(owner, false, instant("2026-01-10"), instant("2026-01-20"), null);
        UUID noExifJanuary = insertPhoto(owner, false, null, instant("2026-01-05"), null);
        UUID noExifFebruary = insertPhoto(owner, false, null, instant("2026-02-01"), null);
        UUID deletedFileFebruary = insertPhoto(owner, true, null, instant("2026-02-02"), null);

        List<PhotoGroupPreviewProjection> page =
                photoItemRepository.findGroupPreviewPage(owner, "DATE", ZONE_ID, 0, 20);

        assertThat(page.stream()
                .map(PhotoGroupPreviewProjection::getGroupKey)
                .distinct()
                .toList()).containsExactlyInAnyOrder("2026-01", "2026-02");
        assertThat(page).extracting(PhotoGroupPreviewProjection::getId)
                .contains(exifPhoto, noExifJanuary, noExifFebruary)
                .doesNotContain(deletedFileFebruary);
        assertThat(page.stream()
                .filter(row -> "2026-01".equals(row.getGroupKey()))
                .map(PhotoGroupPreviewProjection::getId)
                .toList()).containsExactly(exifPhoto, noExifJanuary);
        assertThat(page.stream()
                .filter(row -> "2026-01".equals(row.getGroupKey()))
                .map(PhotoGroupPreviewProjection::getPhotoCount)
                .distinct()
                .toList()).containsExactly(2L);
        assertThat(page.stream()
                .filter(row -> "2026-02".equals(row.getGroupKey()))
                .map(PhotoGroupPreviewProjection::getId)
                .toList()).containsExactly(noExifFebruary);
    }

    @Test
    @DisplayName("Outbox 显式列查询能完整映射同步事件与投递记录")
    void outboxExplicitColumnsMapBackToEntities() {
        UUID eventId = UUID.randomUUID();
        UUID recipient = UUID.randomUUID();
        jdbcTemplate.update("""
                INSERT INTO omni.sync_events
                    (id, recipient_user_id, scope, resource_type, resource_id, action,
                     resource_version, payload, publish_status, available_at, created_at, updated_at, version)
                VALUES (?, ?, 'FILES', 'FILE_NODE', ?, 'CREATED', 3, '{"x":1}'::jsonb,
                        'PENDING', now(), now(), now(), 0)
                """, eventId, recipient, UUID.randomUUID().toString());
        UUID dispatchId = UUID.randomUUID();
        UUID taskId = UUID.randomUUID();
        jdbcTemplate.update("""
                INSERT INTO omni.sys_task_dispatches
                    (id, task_id, exchange_name, routing_key, payload, status,
                     next_attempt_at, created_at, updated_at, version)
                VALUES (?, ?, 'omni.task', 'review.test', '{"taskId":"x"}', 'PENDING',
                        now(), now(), now(), 0)
                """, dispatchId, taskId);

        TransactionTemplate transaction = new TransactionTemplate(transactionManager);
        transaction.executeWithoutResult(status -> {
            List<SyncEvent> events = syncEventRepository.findClaimableEvents(Instant.now(), 20);
            SyncEvent event = events.stream()
                    .filter(candidate -> eventId.equals(candidate.getId()))
                    .findFirst()
                    .orElseThrow();
            assertThat(event.getRecipientUserId()).isEqualTo(recipient);
            assertThat(event.getScope().name()).isEqualTo("FILES");
            assertThat(event.getResourceType()).isEqualTo("FILE_NODE");
            assertThat(event.getAction().name()).isEqualTo("CREATED");
            assertThat(event.getResourceVersion()).isEqualTo(3L);
            assertThat(event.getPayload()).containsEntry("x", 1);
            assertThat(event.getPublishStatus()).isEqualTo("PENDING");
            assertThat(event.getVersion()).isZero();
            assertThat(event.getSequenceNo()).isNotNull();

            List<TaskDispatch> dispatches = taskDispatchRepository.findClaimable(Instant.now(), 20);
            TaskDispatch dispatch = dispatches.stream()
                    .filter(candidate -> dispatchId.equals(candidate.getId()))
                    .findFirst()
                    .orElseThrow();
            assertThat(dispatch.getTaskId()).isEqualTo(taskId);
            assertThat(dispatch.getExchangeName()).isEqualTo("omni.task");
            assertThat(dispatch.getRoutingKey()).isEqualTo("review.test");
            assertThat(dispatch.getPayload()).isEqualTo("{\"taskId\":\"x\"}");
            assertThat(dispatch.getStatus()).isEqualTo("PENDING");
            assertThat(dispatch.getVersion()).isZero();
            status.setRollbackOnly();
        });
    }

    @Test
    @DisplayName("歌单曲目分页由数据库按 sort_order 下推，不再内存切片")
    void playlistPageQueryPushesPagingToSql() {
        UUID owner = UUID.randomUUID();
        UUID playlistId = UUID.randomUUID();
        jdbcTemplate.update("""
                INSERT INTO omni.music_playlists
                    (id, owner_user_id, name, playlist_type, created_at, updated_at, version)
                VALUES (?, ?, 'IT Playlist', 'CUSTOM', now(), now(), 0)
                """, playlistId, owner);
        for (int index = 0; index < 25; index++) {
            jdbcTemplate.update("""
                    INSERT INTO omni.music_playlist_items
                        (id, owner_user_id, playlist_id, track_id, sort_order, created_at, version)
                    VALUES (?, ?, ?, ?, ?, now(), 0)
                    """, UUID.randomUUID(), owner, playlistId, UUID.randomUUID(), index);
        }

        Page<MusicPlaylistItem> page = playlistItemRepository
                .findByOwnerUserIdAndPlaylistIdOrderBySortOrderAscCreatedAtAsc(
                        owner, playlistId, PageRequest.of(1, 10));

        assertThat(page.getTotalElements()).isEqualTo(25);
        assertThat(page.getContent()).hasSize(10);
        assertThat(page.getContent()).extracting(MusicPlaylistItem::getSortOrder)
                .containsExactly(10, 11, 12, 13, 14, 15, 16, 17, 18, 19);
    }

    private UUID insertAlbum(UUID ownerUserId, String name) {
        UUID albumId = UUID.randomUUID();
        jdbcTemplate.update("""
                INSERT INTO omni.photo_albums
                    (id, owner_user_id, name, photo_count, created_at, updated_at, version)
                VALUES (?, ?, ?, 0, now(), now(), 0)
                """, albumId, ownerUserId, name);
        return albumId;
    }

    private void addToAlbum(UUID ownerUserId, UUID albumId, UUID photoId) {
        jdbcTemplate.update("""
                INSERT INTO omni.photo_album_items
                    (id, owner_user_id, album_id, photo_id, sort_order, created_at, version)
                VALUES (?, ?, ?, ?, 0, now(), 0)
                """, UUID.randomUUID(), ownerUserId, albumId, photoId);
    }

    private UUID insertPhoto(
            UUID ownerUserId,
            boolean fileDeleted,
            Instant dateTaken,
            Instant createdAt,
            String city
    ) {
        UUID fileNodeId = UUID.randomUUID();
        UUID objectId = insertObject();
        jdbcTemplate.update("""
                INSERT INTO omni.file_nodes
                    (id, owner_user_id, node_type, name, normalized_path, mime_type, size_bytes,
                     current_object_id, source_type, is_deleted, created_at, updated_at, version, space_type)
                VALUES (?, ?, 'FILE', 'photo.jpg', ?, 'image/jpeg', 2048, ?, 'LOCAL', ?, ?, ?, 0, 'PERSONAL')
                """, fileNodeId, ownerUserId, "/Photos/it-" + fileNodeId + "/photo.jpg", objectId,
                fileDeleted, Timestamp.from(createdAt), Timestamp.from(createdAt));
        UUID photoId = UUID.randomUUID();
        jdbcTemplate.update("""
                INSERT INTO omni.photo_items
                    (id, owner_user_id, file_node_id, title, date_taken, format, file_size,
                     metadata_status, created_at, updated_at, version)
                VALUES (?, ?, ?, 'IT Photo', ?, 'jpg', 2048, 'MATCHED', ?, ?, 0)
                """, photoId, ownerUserId, fileNodeId, dateTaken == null ? null : Timestamp.from(dateTaken),
                Timestamp.from(createdAt), Timestamp.from(createdAt));
        if (city != null) {
            jdbcTemplate.update(
                    "UPDATE omni.photo_items SET gps_location = jsonb_build_object('city', ?) WHERE id = ?",
                    city, photoId);
        }
        return photoId;
    }

    private UUID insertObject() {
        UUID objectId = UUID.randomUUID();
        jdbcTemplate.update("""
                INSERT INTO omni.file_objects (id, bucket_name, object_key, size_bytes, created_at)
                VALUES (?, 'omninest-user-files', ?, 2048, now())
                """, objectId, "photos/it-" + objectId);
        return objectId;
    }

    private static Instant instant(String localDate) {
        return LocalDate.parse(localDate).atStartOfDay(ZoneOffset.UTC).toInstant();
    }

    /**
     * 外部基础设施替换为测试边界：对象存储与 AMQP 管理不需要真实实例。
     */
    @TestConfiguration(proxyBeanMethods = false)
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
