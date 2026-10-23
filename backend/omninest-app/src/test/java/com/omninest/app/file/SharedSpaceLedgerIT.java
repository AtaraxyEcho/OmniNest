package com.omninest.app.file;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.omninest.OmniNestApplication;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.common.storage.ObjectStorageKey;
import com.omninest.common.util.LikePatterns;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.repository.FileMetricsRepository;
import com.omninest.modules.file.repository.FileNodeRepository;
import com.omninest.modules.file.service.SharedSpaceQuotaService;
import com.omninest.modules.music.domain.MusicTrack;
import com.omninest.modules.music.repository.MusicTrackRepository;
import com.omninest.modules.photos.repository.PhotoAlbumItemRepository;
import com.omninest.modules.photos.repository.PhotoItemRepository;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.LinkedHashMap;
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
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * 存储账本与分页查询的真库集成测试。
 *
 * <p>本轮修复把三类判定从 Java 挪进了 SQL：共享空间容量守卫进 {@code WHERE}、字节与文件数
 * 扣减夹零进 {@code CASE}、子树统计改按空间前缀并依赖 ESCAPE 声明、专辑曲目分页新增显式
 * countQuery。这些都只在真实 PostgreSQL 上执行才会暴露，上下文冒烟仅解析 HQL 不跑 SQL，
 * 单元测试用 Mock 更是永远"绿"。</p>
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
                "omninest.search.index-path=${java.io.tmpdir}/omninest-ledger-sql-it"
        }
)
@ActiveProfiles("dev")
@Testcontainers(disabledWithoutDocker = true)
@Import(SharedSpaceLedgerIT.ExternalDependencyOverrides.class)
class SharedSpaceLedgerIT {

    private static final String IMAGE = "postgres:18-alpine";
    private static final String SHARE_MAX_BYTES_KEY = "share.max-bytes";

    @Container
    private static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>(IMAGE)
            .withDatabaseName("omninest_ledger_it")
            .withUsername("omninest")
            .withPassword("omninest");

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @Autowired
    private SharedSpaceQuotaService sharedSpaceQuotaService;

    @Autowired
    private FileNodeRepository fileNodeRepository;

    @Autowired
    private FileMetricsRepository fileMetricsRepository;

    @Autowired
    private PhotoAlbumItemRepository photoAlbumItemRepository;
    @Autowired
    private PhotoItemRepository photoItemRepository;

    @Autowired
    private MusicTrackRepository musicTrackRepository;

    @DynamicPropertySource
    static void registerDatabaseProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", POSTGRES::getJdbcUrl);
        registry.add("spring.datasource.username", POSTGRES::getUsername);
        registry.add("spring.datasource.password", POSTGRES::getPassword);
    }

    @Test
    @DisplayName("容量守卫与增量同条 UPDATE：放得下才记账")
    void increaseUsageWithinCeilingUpdatesBothCountersAndVersion() {
        UUID usageId = freshUsage(1_000L, 2L, 0L);
        shareCeiling(10_000L);

        sharedSpaceQuotaService.increaseUsage(500L, 3L);

        assertThat(usedBytes(usageId)).isEqualTo(1_500L);
        assertThat(fileCount(usageId)).isEqualTo(5L);
        assertThat(version(usageId)).isEqualTo(1L);
    }

    @Test
    @DisplayName("超出容量时字节与文件数一分不动，守卫不是读后再判")
    void increaseUsageOverCeilingLeavesLedgerUntouched() {
        UUID usageId = freshUsage(9_800L, 2L, 4L);
        shareCeiling(10_000L);

        assertThatThrownBy(() -> sharedSpaceQuotaService.increaseUsage(500L, 3L))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.FILE_QUOTA_EXCEEDED);

        assertThat(usedBytes(usageId)).isEqualTo(9_800L);
        assertThat(fileCount(usageId)).isEqualTo(2L);
        assertThat(version(usageId)).isEqualTo(4L);
    }

    @Test
    @DisplayName("扣减夹到零，不把账本写成负数")
    void decreaseUsageClampsBothCountersAtZero() {
        UUID usageId = freshUsage(100L, 1L, 0L);

        sharedSpaceQuotaService.decreaseUsage(500L, 5L);

        assertThat(usedBytes(usageId)).isZero();
        assertThat(fileCount(usageId)).isZero();
        assertThat(version(usageId)).isEqualTo(1L);
    }

    @Test
    @DisplayName("版本字节按对象去重：重复 RESTORE 行不会放大删除/恢复配额")
    void versionBytesDeduplicateObjects() {
        UUID owner = UUID.randomUUID();
        UUID nodeId = UUID.randomUUID();
        UUID currentObject = insertObject("current-object", 1024);
        insertPersonalFileNode(nodeId, owner, "/docs/file.bin", 1024, currentObject, false);
        UUID versionObject = insertObject("version-object", 4096);
        insertVersion(nodeId, versionObject, 1);
        insertVersion(nodeId, versionObject, 2);

        long nodeBytes = fileMetricsRepository.sumVersionBytesForNode(
                nodeId, SpaceType.PERSONAL.getValue(), false);
        long ownerBytes = fileMetricsRepository.sumVersionBytesUnderPathByOwner(
                owner, "/docs/", false);

        assertThat(nodeBytes).isEqualTo(4096L);
        assertThat(ownerBytes).isEqualTo(4096L);
    }

    @Test
    @DisplayName("共享子树的版本字节按节点+对象去重")
    void sharedSubtreeVersionBytesDeduplicateObjects() {
        UUID owner = UUID.randomUUID();
        UUID nodeId = UUID.randomUUID();
        UUID currentObject = insertObject("shared-current", 1024);
        insertPersonalFileNode(nodeId, owner, "/share/file.bin", 1024, currentObject, false);
        jdbcTemplate.update("UPDATE omni.file_nodes SET space_type = 'SHARED' WHERE id = ?", nodeId);
        UUID versionObject = insertObject("shared-version", 2048);
        insertVersion(nodeId, versionObject, 1);
        insertVersion(nodeId, versionObject, 2);

        long sharedBytes = fileMetricsRepository.sumVersionBytesUnderPathInSpace(
                SpaceType.SHARED.getValue(), "/share/", false);

        assertThat(sharedBytes).isEqualTo(2048L);
    }

    @Test
    @DisplayName("共享子树统计按空间与前缀，含其他成员文件且转义生效")
    void sharedSubtreeAggregateCoversEveryOwnerAndEscapesPrefix() {
        UUID ownerA = UUID.randomUUID();
        UUID ownerB = UUID.randomUUID();
        // 目录名里的下划线是字面量：不声明 ESCAPE 时会退化成单字符通配，把兄弟目录整棵子树算进来。
        String folderPath = "/S_T/a";
        UUID folder = insertSharedNode(ownerA, folderPath, "FOLDER", 0L, false);
        insertSharedNode(ownerA, folderPath + "/mine.pdf", "FILE", 400L, false);
        UUID otherOwnerFile = insertSharedNode(ownerB, folderPath + "/theirs.pdf", "FILE", 900L, false);
        insertSharedNode(ownerA, folderPath + "/gone.pdf", "FILE", 5_000L, true);
        insertSharedNode(ownerB, folderPath + "X/inside-other-folder.pdf", "FILE", 7_000L, false);
        String prefix = LikePatterns.escapeSpecials(folderPath + "/");

        List<Object[]> inSpace = fileNodeRepository.sumActiveFilesUnderPathInSpace(
                SpaceType.SHARED, prefix);
        List<Object[]> byOwner = fileNodeRepository.sumActiveFilesUnderPathByOwner(
                ownerA, SpaceType.SHARED, prefix);

        assertThat(inSpace).hasSize(1);
        // 共享目录内文件所有者各不相同，按创建者过滤会漏掉 ownerB 的 900 字节（被删的 5000 不算）。
        assertThat(number(inSpace.getFirst()[0])).isEqualTo(1_300L);
        assertThat(number(inSpace.getFirst()[1])).isEqualTo(2L);
        assertThat(number(byOwner.getFirst()[0])).isEqualTo(400L);
        assertThat(number(byOwner.getFirst()[1])).isEqualTo(1L);
        assertThat(otherOwnerFile).isNotNull();
        assertThat(folder).isNotNull();
    }

    @Test
    @DisplayName("相册计数只数活动照片，回收站与软删文件节点都不计入")
    void albumCountExcludesTrashedAndSoftDeletedPhotos() {
        UUID owner = UUID.randomUUID();
        UUID albumId = insertAlbum(owner, 99);
        UUID activePhoto = insertPhoto(owner, "active.jpg", 1_024L, null);
        UUID trashedPhoto = insertPhoto(owner, "trashed.jpg", 2_048L, Instant.now());
        UUID deletedFilePhoto = insertPhoto(owner, "deleted-file.jpg", 4_096L, null);
        markPhotoFileDeleted(deletedFilePhoto);
        insertAlbumItem(owner, albumId, activePhoto);
        insertAlbumItem(owner, albumId, trashedPhoto);
        insertAlbumItem(owner, albumId, deletedFilePhoto);

        assertThat(photoAlbumItemRepository.countByAlbumId(albumId)).isEqualTo(3L);
        assertThat(photoAlbumItemRepository.countActivePhotosByAlbumId(albumId)).isEqualTo(1L);
    }

    @Test
    @DisplayName("关系图谱聚合排除回收站照片，且全部图谱 SQL 可在真实库执行")
    void relationGraphAggregationsExcludeTrashedPhotos() {
        UUID owner = UUID.randomUUID();
        UUID firstAlbum = insertAlbum(owner, 0);
        UUID secondAlbum = insertAlbum(owner, 0);
        UUID activePhoto = insertPhoto(owner, "graph-active.jpg", 1_024L, null);
        UUID trashedPhoto = insertPhoto(owner, "graph-trashed.jpg", 2_048L, Instant.now());
        for (UUID albumId : List.of(firstAlbum, secondAlbum)) {
            insertAlbumItem(owner, albumId, activePhoto);
            insertAlbumItem(owner, albumId, trashedPhoto);
        }

        var edges = photoItemRepository.findAlbumAlbumRelationEdges(owner, 50);

        // 共享照片是再次关联的唯一依据：回收站照片不能贡献边权重。
        assertThat(edges).hasSize(1);
        assertThat(edges.getFirst().getWeight()).isEqualTo(1L);
        // 未写入 date_taken 的照片不进时间维度；位置维度按“未知位置”聚合，
        // 权重必须等于活动照片数，否则回收站照片会继续给图谱加权。
        assertThat(photoItemRepository.findAlbumTimeRelationEdges(owner, "UTC", 50)).isEmpty();
        assertThat(photoItemRepository.findTimeLocationRelationEdges(owner, "UTC", 50)).isEmpty();
        assertThat(photoItemRepository.findTimeRelationNodes(owner, "UTC", 50)).isEmpty();
        assertThat(photoItemRepository.findAlbumLocationRelationEdges(owner, 50)).hasSize(2)
                .allSatisfy(edge -> assertThat(edge.getWeight()).isEqualTo(1L));
        assertThat(photoItemRepository.findAlbumRelationNodes(owner, 50)).hasSize(2);
        var locationNodes = photoItemRepository.findLocationRelationNodes(owner, 50);
        assertThat(locationNodes).hasSize(1);
        // 未知位置只有一组，权重必须等于活动照片数（软删照片被排除后不再+1）。
        assertThat(locationNodes.getFirst().getWeight()).isEqualTo(1L);
    }

    @Test
    @DisplayName("曲目分页的内容与总数共用同一谓词，软删文件两边都不算")
    void albumTracksPageSharesPredicateBetweenContentAndCount() {
        UUID owner = UUID.randomUUID();
        UUID albumId = insertMusicAlbum(owner);
        insertTrack(owner, albumId, "第一首", false);
        insertTrack(owner, albumId, "第二首", false);
        insertTrack(owner, albumId, "已删", true);
        Pageable firstPage = PageRequest.of(0, 1);

        var page = musicTrackRepository.findAlbumTracksPage(owner, albumId, firstPage);

        // 内容页与总数必须共用同一谓词：countQuery 少写联接条件时总数会算进已删文件。
        assertThat(page.getContent()).hasSize(1);
        assertThat(page.getTotalElements()).isEqualTo(2L);
    }

    @Test
    @DisplayName("个人用量重算与配额账本同口径：回收站与历史版本都算，换位不重复计")
    void personalUsageRecalculationMatchesQuotaLedger() {
        UUID owner = UUID.randomUUID();
        UUID sharedOwner = UUID.randomUUID();

        // 活动文件：节点自身 1000 + 一个不同引用的历史版本 700。
        UUID nodeId = UUID.randomUUID();
        UUID currentObject = insertObject("/u/a.bin", 1000L);
        UUID historyObject = insertObject("/u/a-old.bin", 700L);
        insertPersonalFileNode(nodeId, owner, "/a.bin", 1000L, currentObject, false);
        insertVersion(nodeId, historyObject, 1);

        // 恢复历史版本只让对象在当前对象与版本行之间换位：同对象的两条版本行都不另计。
        UUID restoredNode = UUID.randomUUID();
        UUID restoredObject = insertObject("/u/b.bin", 300L);
        insertPersonalFileNode(restoredNode, owner, "/b.bin", 300L, restoredObject, false);
        insertVersion(restoredNode, restoredObject, 1);
        insertVersion(restoredNode, restoredObject, 2);

        // 同一节点内同一对象反复入版本表，只在创建时计一次。
        UUID duplicatedNode = UUID.randomUUID();
        UUID duplicatedCurrent = insertObject("/u/c.bin", 50L);
        UUID duplicatedHistory = insertObject("/u/c-old.bin", 60L);
        insertPersonalFileNode(duplicatedNode, owner, "/c.bin", 50L, duplicatedCurrent, false);
        insertVersion(duplicatedNode, duplicatedHistory, 1);
        insertVersion(duplicatedNode, duplicatedHistory, 2);

        // 回收站里的文件在彻底删除前一直占配额。
        insertPersonalFileNode(UUID.randomUUID(), owner, "/trash.bin", 400L,
                insertObject("/u/trash.bin", 400L), true);
        // 共享空间节点不进个人账本。
        insertSharedNode(sharedOwner, "/shared.bin", "FILE", 5000L, false);
        // 系统派生与只读本地库节点写入时从未加计，重算基数必须同样排除，
        // 否则一次夜间对账就把缩略图与挂载影片全额塞进个人已用配额。
        insertPersonalFileNodeWithSource(UUID.randomUUID(), owner,
                "/.metadata/PHOTO_ITEM/" + nodeId + "/THUMBNAIL/thumb.jpg", 30_000L, "DERIVED");
        insertPersonalFileNodeWithSource(UUID.randomUUID(), owner,
                "/.metadata/LOCAL_MEDIA/" + nodeId + "/SOURCE.mkv", 7_000_000L, "LOCAL_FILESYSTEM");
        // 例外：背景图原片与编辑版本写入时已加计，必须留在基数内，否则夜间被抹掉而删除时再扣一次。
        insertPersonalFileNodeWithSource(UUID.randomUUID(), owner,
                "/.metadata/BACKDROP/" + nodeId + "/ORIGINAL/wallpaper.png", 2_500L, "DERIVED");
        insertPersonalFileNodeWithSource(UUID.randomUUID(), owner,
                "/.metadata/PHOTO_ITEM/" + nodeId + "/EDIT_VERSION/edited.jpg", 120L, "DERIVED");

        Map<UUID, Long> usage = new LinkedHashMap<>();
        fileMetricsRepository.sumFileSizeForUsers(List.of(owner, sharedOwner))
                .forEach(row -> usage.put(row.getUserId(), row.getTotalBytes()));

        assertThat(usage.get(owner))
                .isEqualTo(1000L + 700L + 300L + 50L + 60L + 400L + 2_500L + 120L);
        assertThat(usage).doesNotContainKey(sharedOwner);
    }

    @Test
    @DisplayName("共享账本对账与写入侧同口径：软删与只计换位版本都不重复计")
    void sharedLedgerReconciliationMatchesWriteSide() {
        clearSharedSpaceNodes();
        UUID owner = UUID.randomUUID();

        // 活动文件：节点 1000 + 一个不同引用的历史版本 700。
        UUID historyObject = insertObject("/s/a-old.bin", 700L);
        UUID firstNode = insertSharedNode(owner, "/s/a.bin", "FILE", 1000L,
                insertObject("/s/a.bin", 1000L), null, false);
        insertVersion(firstNode, historyObject, 1);

        // 恢复历史版本只换位：与当前对象同引用的版本行不另计字节。
        UUID restoredObject = insertObject("/s/b.bin", 300L);
        UUID secondNode = insertSharedNode(owner, "/s/b.bin", "FILE", 300L, restoredObject, null, false);
        insertVersion(secondNode, restoredObject, 1);

        // 共享账本在软删除时就扣减，回收站节点不进对账基数。
        insertSharedNode(owner, "/s/trash.bin", "FILE", 400L,
                insertObject("/s/trash.bin", 400L), null, true);
        // 目录不计字节也不计文件。
        insertSharedNode(owner, "/s/folder", "FOLDER", 0L, null, null, false);
        // 派生缩略图从不加计；背景图原片写入时已全额加计，必须留在基数内。
        insertSharedNode(owner, "/.metadata/PHOTO_ITEM/" + firstNode + "/THUMBNAIL/thumb.jpg",
                "FILE", 30_000L, insertObject("/s/thumb.jpg", 30_000L), "DERIVED", false);
        insertSharedNode(owner, "/.metadata/BACKDROP/" + firstNode + "/ORIGINAL/wall.png",
                "FILE", 2_500L, insertObject("/s/wall.png", 2_500L), "DERIVED", false);
        insertSharedNode(owner, "/.metadata/LOCAL_MEDIA/" + firstNode + "/SOURCE.mkv",
                "FILE", 7_000_000L, insertObject("/s/source.mkv", 7_000_000L), "LOCAL_FILESYSTEM", false);

        var actual = fileMetricsRepository.aggregateSharedSpaceUsage();
        assertThat(actual.getTotalBytes()).isEqualTo(1000L + 700L + 300L + 2_500L);
        assertThat(actual.getTotalFiles()).isEqualTo(3L);

        UUID usageId = freshUsage(9_999L, 99L, 0L);
        sharedSpaceQuotaService.reconcileUsage();
        assertThat(usedBytes(usageId)).isEqualTo(4_500L);
        assertThat(fileCount(usageId)).isEqualTo(3L);
        assertThat(version(usageId)).isEqualTo(1L);

        // 已一致时条件更新不动行，避免每天无谓推高乐观锁版本。
        sharedSpaceQuotaService.reconcileUsage();
        assertThat(version(usageId)).isEqualTo(1L);
    }

    // ── 种子与读取 ────────────────────────────────────────────────────────

    /**
     * 共享账本对账只在空间维度聚合，先清掉其他用例留下的共享节点，计数才只反映本用例的种子。
     */
    private void clearSharedSpaceNodes() {
        jdbcTemplate.update("""
                delete from omni.file_versions
                where file_node_id in (
                    select id from omni.file_nodes where space_type = 'SHARED')
                """);
        jdbcTemplate.update("delete from omni.file_nodes where space_type = 'SHARED'");
    }

    private UUID freshUsage(long usedBytes, long fileCount, long version) {
        jdbcTemplate.update("delete from omni.shared_space_usage");
        UUID id = UUID.randomUUID();
        Instant now = Instant.now();
        jdbcTemplate.update("""
                INSERT INTO omni.shared_space_usage
                    (id, used_bytes, file_count, created_at, updated_at, version)
                VALUES (?, ?, ?, ?, ?, ?)
                """, id, usedBytes, fileCount, Timestamp.from(now), Timestamp.from(now), version);
        return id;
    }

    private void shareCeiling(long maxBytes) {
        int updated = jdbcTemplate.update(
                "update omni.config_entries set config_value = ? where config_key = ?",
                String.valueOf(maxBytes), SHARE_MAX_BYTES_KEY);
        // 内置目录缺这一项时服务会回落到 100GB 默认值，用例就会在错误的上限上"通过"。
        assertThat(updated).as("share.max-bytes 必须由内置目录种子提供").isEqualTo(1);
    }

    private long usedBytes(UUID usageId) {
        return jdbcTemplate.queryForObject(
                "select used_bytes from omni.shared_space_usage where id = ?", Long.class, usageId);
    }

    private long fileCount(UUID usageId) {
        return jdbcTemplate.queryForObject(
                "select file_count from omni.shared_space_usage where id = ?", Long.class, usageId);
    }

    private long version(UUID usageId) {
        return jdbcTemplate.queryForObject(
                "select version from omni.shared_space_usage where id = ?", Long.class, usageId);
    }

    private long number(Object value) {
        return ((Number) value).longValue();
    }

    private UUID insertSharedNode(
            UUID ownerUserId,
            String normalizedPath,
            String nodeType,
            long sizeBytes,
            boolean deleted
    ) {
        return insertSharedNode(ownerUserId, normalizedPath, nodeType, sizeBytes, null, null, deleted);
    }

    private UUID insertSharedNode(
            UUID ownerUserId,
            String normalizedPath,
            String nodeType,
            long sizeBytes,
            UUID currentObjectId,
            String sourceType,
            boolean deleted
    ) {
        UUID nodeId = UUID.randomUUID();
        Instant now = Instant.now();
        // 显式写 NULL 会绕过列上的 DEFAULT 'LOCAL'，直接撞上 NOT NULL 约束。
        String effectiveSourceType = sourceType == null ? "LOCAL" : sourceType;
        jdbcTemplate.update("""
                INSERT INTO omni.file_nodes
                    (id, owner_user_id, node_type, name, normalized_path, size_bytes,
                     current_object_id, is_deleted, space_type, source_type, created_at, updated_at, version)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'SHARED', ?, ?, ?, 0)
                """, nodeId, ownerUserId, nodeType,
                normalizedPath.substring(normalizedPath.lastIndexOf('/') + 1),
                normalizedPath, sizeBytes, currentObjectId, deleted, effectiveSourceType,
                Timestamp.from(now), Timestamp.from(now));
        return nodeId;
    }

    private UUID insertAlbum(UUID ownerUserId, int photoCount) {
        UUID albumId = UUID.randomUUID();
        Instant now = Instant.now();
        jdbcTemplate.update("""
                INSERT INTO omni.photo_albums
                    (id, owner_user_id, name, photo_count, created_at, updated_at, version)
                VALUES (?, ?, ?, ?, ?, ?, 0)
                """, albumId, ownerUserId, "测试相册 " + albumId, photoCount,
                Timestamp.from(now), Timestamp.from(now));
        return albumId;
    }

    private UUID insertPhoto(UUID ownerUserId, String name, long sizeBytes, Instant deletedAt) {
        UUID fileNodeId = insertPersonalFile(ownerUserId, "/" + name, sizeBytes, deletedAt != null);
        UUID photoId = UUID.randomUUID();
        Instant now = Instant.now();
        jdbcTemplate.update("""
                INSERT INTO omni.photo_items
                    (id, owner_user_id, file_node_id, title, file_size, deleted_at,
                     created_at, updated_at, version)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0)
                """, photoId, ownerUserId, fileNodeId, name, sizeBytes,
                deletedAt == null ? null : Timestamp.from(deletedAt),
                Timestamp.from(now), Timestamp.from(now));
        return photoId;
    }

    private void markPhotoFileDeleted(UUID photoId) {
        jdbcTemplate.update("""
                update omni.file_nodes set is_deleted = true
                where id = (select file_node_id from omni.photo_items where id = ?)
                """, photoId);
    }

    private void insertAlbumItem(UUID ownerUserId, UUID albumId, UUID photoId) {
        jdbcTemplate.update("""
                INSERT INTO omni.photo_album_items
                    (id, owner_user_id, album_id, photo_id, sort_order, created_at, version)
                VALUES (?, ?, ?, ?, 0, ?, 0)
                """, UUID.randomUUID(), ownerUserId, albumId, photoId, Timestamp.from(Instant.now()));
    }

    private UUID insertMusicAlbum(UUID ownerUserId) {
        UUID albumId = UUID.randomUUID();
        Instant now = Instant.now();
        jdbcTemplate.update("""
                INSERT INTO omni.music_albums
                    (id, owner_user_id, title, created_at, updated_at, version)
                VALUES (?, ?, ?, ?, ?, 0)
                """, albumId, ownerUserId, "测试专辑 " + albumId,
                Timestamp.from(now), Timestamp.from(now));
        return albumId;
    }

    private void insertTrack(UUID ownerUserId, UUID albumId, String title, boolean fileDeleted) {
        UUID fileNodeId = insertPersonalFile(ownerUserId, "/Music/" + title + ".flac", 512L, fileDeleted);
        Instant now = Instant.now();
        jdbcTemplate.update("""
                INSERT INTO omni.music_tracks
                    (id, owner_user_id, file_node_id, album_id, title, created_at, updated_at, version)
                VALUES (?, ?, ?, ?, ?, ?, ?, 0)
                """, UUID.randomUUID(), ownerUserId, fileNodeId, albumId, title,
                Timestamp.from(now), Timestamp.from(now));
    }

    private UUID insertPersonalFile(UUID ownerUserId, String normalizedPath, long sizeBytes, boolean deleted) {
        UUID nodeId = UUID.randomUUID();
        UUID objectId = insertObject(normalizedPath);
        Instant now = Instant.now();
        jdbcTemplate.update("""
                INSERT INTO omni.file_nodes
                    (id, owner_user_id, node_type, name, normalized_path, size_bytes,
                     current_object_id, is_deleted, space_type, created_at, updated_at, version)
                VALUES (?, ?, 'FILE', ?, ?, ?, ?, ?, 'PERSONAL', ?, ?, 0)
                """, nodeId, ownerUserId, normalizedPath.substring(normalizedPath.lastIndexOf('/') + 1),
                normalizedPath, sizeBytes, objectId, deleted,
                Timestamp.from(now), Timestamp.from(now));
        return nodeId;
    }

    private UUID insertObject(String objectKey) {
        return insertObject(objectKey, 1024L);
    }

    private UUID insertObject(String objectKey, long sizeBytes) {
        UUID objectId = UUID.randomUUID();
        Instant now = Instant.now();
        jdbcTemplate.update("""
                INSERT INTO omni.file_objects
                    (id, bucket_name, object_key, size_bytes, created_at, updated_at, version)
                VALUES (?, 'user-files', ?, ?, ?, ?, 0)
                """, objectId, objectKey, sizeBytes, Timestamp.from(now), Timestamp.from(now));
        return objectId;
    }

    private UUID insertPersonalFileNode(
            UUID nodeId,
            UUID ownerUserId,
            String normalizedPath,
            long sizeBytes,
            UUID currentObjectId,
            boolean deleted
    ) {
        Instant now = Instant.now();
        jdbcTemplate.update("""
                INSERT INTO omni.file_nodes
                    (id, owner_user_id, node_type, name, normalized_path, size_bytes,
                     current_object_id, is_deleted, space_type, created_at, updated_at, version)
                VALUES (?, ?, 'FILE', ?, ?, ?, ?, ?, 'PERSONAL', ?, ?, 0)
                """, nodeId, ownerUserId,
                normalizedPath.substring(normalizedPath.lastIndexOf('/') + 1),
                normalizedPath, sizeBytes, currentObjectId, deleted,
                Timestamp.from(now), Timestamp.from(now));
        return nodeId;
    }

    private UUID insertPersonalFileNodeWithSource(
            UUID nodeId,
            UUID ownerUserId,
            String normalizedPath,
            long sizeBytes,
            String sourceType
    ) {
        Instant now = Instant.now();
        UUID objectId = insertObject(normalizedPath, sizeBytes);
        jdbcTemplate.update("""
                INSERT INTO omni.file_nodes
                    (id, owner_user_id, node_type, name, normalized_path, size_bytes,
                     current_object_id, is_deleted, space_type, source_type, created_at, updated_at, version)
                VALUES (?, ?, 'FILE', ?, ?, ?, ?, false, 'PERSONAL', ?, ?, ?, 0)
                """, nodeId, ownerUserId,
                normalizedPath.substring(normalizedPath.lastIndexOf('/') + 1),
                normalizedPath, sizeBytes, objectId, sourceType,
                Timestamp.from(now), Timestamp.from(now));
        return nodeId;
    }

    private void insertVersion(UUID nodeId, UUID objectId, int versionNo) {
        Instant now = Instant.now();
        jdbcTemplate.update("""
                INSERT INTO omni.file_versions
                    (id, file_node_id, object_id, version_no, change_type, created_at, version)
                VALUES (?, ?, ?, ?, 'EDIT', ?, 0)
                """, UUID.randomUUID(), nodeId, objectId, versionNo, Timestamp.from(now));
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
