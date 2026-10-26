package com.omninest.app.photos;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.omninest.OmniNestApplication;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.common.storage.ObjectStorageKey;
import com.omninest.modules.photos.repository.PhotoIndexTargetProjection;
import com.omninest.modules.photos.repository.PhotoItemRepository;
import com.omninest.modules.photos.repository.PhotoTimelinePreviewProjection;
import java.sql.Timestamp;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.stream.Collectors;
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
import org.springframework.data.domain.PageRequest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.springframework.test.annotation.DirtiesContext;

/**
 * 照片时间线月份分组一致性集成测试。
 *
 * <p>时间线分页与月份计数都是原生 SQL：月份键在 preview 与 count 两处必须一致地
 * COALESCE(date_taken, created_at)，且过滤集相同，否则无 EXIF 照片会让月份卡片出现
 * 有计数无缩略图、totalElements 与分页双向不一致。单元测试与上下文冒烟测试都无法
 * 执行这些原生语句，本测试在真实 PostgreSQL 上按线上数据形态建数据验证结果。</p>
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
                "omninest.search.index-path=${java.io.tmpdir}/omninest-photo-timeline-it"
        }
)
@ActiveProfiles("dev")
@DirtiesContext(classMode = DirtiesContext.ClassMode.AFTER_CLASS)
@Testcontainers(disabledWithoutDocker = true)
@Import(PhotoTimelineMonthConsistencyIT.ExternalDependencyOverrides.class)
class PhotoTimelineMonthConsistencyIT {

    private static final String IMAGE = "postgres:18-alpine";
    private static final String ZONE_ID = "UTC";

    @Container
    private static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>(IMAGE)
            .withDatabaseName("omninest_photo_timeline_it")
            .withUsername("omninest")
            .withPassword("omninest");

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @Autowired
    private PhotoItemRepository photoItemRepository;

    @DynamicPropertySource
    static void registerDatabaseProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", POSTGRES::getJdbcUrl);
        registry.add("spring.datasource.username", POSTGRES::getUsername);
        registry.add("spring.datasource.password", POSTGRES::getPassword);
    }

    @Test
    @DisplayName("无 EXIF 照片按创建时间归档：月份卡片既有计数也有缩略图，月份总数与分页一致")
    void timelineGroupsExiflessPhotosByCreatedAtConsistently() {
        UUID owner = UUID.randomUUID();
        // 一月两张无 EXIF（date_taken 为空，只有 created_at），二月一张无 EXIF，三月一张有 EXIF。
        insertPhoto(owner, null, instant("2026-01-05"));
        insertPhoto(owner, null, instant("2026-01-20"));
        insertPhoto(owner, null, instant("2026-02-11"));
        insertPhoto(owner, instant("2026-03-01"), instant("2026-03-01"));

        long monthTotal = photoItemRepository.countTimelineMonths(owner, ZONE_ID);
        List<PhotoTimelinePreviewProjection> page =
                photoItemRepository.findTimelinePreviewPage(owner, ZONE_ID, 0, 50);

        Map<Integer, Long> previewsByMonth = page.stream()
                .collect(Collectors.groupingBy(PhotoTimelinePreviewProjection::getMonth,
                        Collectors.counting()));
        assertThat(monthTotal).isEqualTo(3L);
        assertThat(previewsByMonth.keySet()).containsExactlyInAnyOrder(1, 2, 3);
        // 每张月份卡片既有计数也有预览缩略图，且计数与实际归档照片数一致。
        assertThat(previewsByMonth.get(1)).isEqualTo(2L);
        assertThat(previewsByMonth.get(2)).isEqualTo(1L);
        assertThat(previewsByMonth.get(3)).isEqualTo(1L);
        page.forEach(row -> {
            assertThat(row.getYear()).isEqualTo(2026);
            long expectedMonthCount = row.getMonth() == 1 ? 2L : 1L;
            assertThat(row.getPhotoCount()).isEqualTo(expectedMonthCount);
        });
    }

    @Test
    @DisplayName("软删与文件删除的照片不进入时间线月份分组")
    void timelineExcludesDeletedPhotosFromBothCountAndPage() {
        UUID owner = UUID.randomUUID();
        insertPhoto(owner, instant("2026-04-01"), instant("2026-04-01"));
        UUID trashedPhoto = insertPhoto(owner, instant("2026-04-02"), instant("2026-04-02"));
        jdbcTemplate.update("UPDATE omni.photo_items SET deleted_at = now() WHERE id = ?", trashedPhoto);
        UUID fileNodeOfDeletedPhoto = UUID.randomUUID();
        insertPhotoWithNode(owner, fileNodeOfDeletedPhoto, instant("2026-04-03"), instant("2026-04-03"));
        jdbcTemplate.update("UPDATE omni.file_nodes SET is_deleted = true WHERE id = ?", fileNodeOfDeletedPhoto);

        long monthTotal = photoItemRepository.countTimelineMonths(owner, ZONE_ID);
        List<PhotoTimelinePreviewProjection> page =
                photoItemRepository.findTimelinePreviewPage(owner, ZONE_ID, 0, 50);

        assertThat(monthTotal).isEqualTo(1L);
        assertThat(page).singleElement().satisfies(row -> {
            assertThat(row.getMonth()).isEqualTo(4);
            assertThat(row.getPhotoCount()).isEqualTo(1L);
        });
    }

    @Test
    @DisplayName("重建候选查询只取活动照片并能解析出所有者投影")
    void indexRebuildScanProjectsOwnerAndExcludesDeletedPhotos() {
        UUID owner = UUID.randomUUID();
        UUID activePhoto = insertPhoto(owner, instant("2026-06-01"), instant("2026-06-01"));
        UUID trashedPhoto = insertPhoto(owner, instant("2026-06-02"), instant("2026-06-02"));
        jdbcTemplate.update("UPDATE omni.photo_items SET deleted_at = now() WHERE id = ?", trashedPhoto);
        UUID deletedFileNodeId = UUID.randomUUID();
        UUID fileDeletedPhoto = insertPhotoWithNode(
                owner, deletedFileNodeId, instant("2026-06-03"), instant("2026-06-03"));
        jdbcTemplate.update("UPDATE omni.file_nodes SET is_deleted = true WHERE id = ?", deletedFileNodeId);

        List<PhotoIndexTargetProjection> page = photoItemRepository.findIndexablePhotosAfterId(
                new UUID(0L, 0L), PageRequest.of(0, 500));
        List<UUID> ownedCandidates = page.stream()
                .filter(row -> owner.equals(row.getOwnerUserId()))
                .map(PhotoIndexTargetProjection::getId)
                .toList();

        // 投影别名写错只会在这里露出来：上下文冒烟只解析 HQL、不执行 SQL，
        // 服务侧单测又是桩掉的仓储，两者都证不到「真查得到、且判据对」。
        assertThat(ownedCandidates).containsExactly(activePhoto);
        assertThat(page).extracting(PhotoIndexTargetProjection::getId)
                .doesNotContain(trashedPhoto, fileDeletedPhoto);
    }

    private UUID insertPhoto(UUID ownerUserId, Instant dateTaken, Instant createdAt) {
        return insertPhotoWithNode(ownerUserId, UUID.randomUUID(), dateTaken, createdAt);
    }

    private UUID insertPhotoWithNode(UUID ownerUserId, UUID fileNodeId, Instant dateTaken, Instant createdAt) {
        UUID objectId = insertObject();
        jdbcTemplate.update("""
                INSERT INTO omni.file_nodes
                    (id, owner_user_id, node_type, name, normalized_path, mime_type, size_bytes,
                     current_object_id, source_type, created_at, updated_at, version, space_type)
                VALUES (?, ?, 'FILE', 'photo.jpg', ?, 'image/jpeg', 2048, ?, 'LOCAL', ?, ?, 0, 'PERSONAL')
                """, fileNodeId, ownerUserId, "/Photos/it-" + fileNodeId + "/photo.jpg", objectId,
                Timestamp.from(createdAt), Timestamp.from(createdAt));
        UUID photoId = UUID.randomUUID();
        jdbcTemplate.update("""
                INSERT INTO omni.photo_items
                    (id, owner_user_id, file_node_id, title, date_taken, format, file_size,
                     metadata_status, created_at, updated_at, version)
                VALUES (?, ?, ?, 'IT Photo', ?, 'jpg', 2048, 'MATCHED', ?, ?, 0)
                """, photoId, ownerUserId, fileNodeId, dateTaken == null ? null : Timestamp.from(dateTaken),
                Timestamp.from(createdAt), Timestamp.from(createdAt));
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
     * 外部基础设施替换为测试边界：对象存储与 AMQP 管理不需要真实实例，
     * 监听容器不得启动，时间线查询只依赖真实 PostgreSQL 元数据。
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
