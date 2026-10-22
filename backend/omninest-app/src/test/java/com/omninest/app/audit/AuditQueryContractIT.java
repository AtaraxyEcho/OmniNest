package com.omninest.app.audit;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.omninest.OmniNestApplication;
import com.omninest.common.error.BusinessException;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.common.storage.ObjectStorageKey;
import com.omninest.common.util.LikePatterns;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.FileShareRecipient;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.service.ExternalStorageOAuthService;
import com.omninest.modules.file.repository.FileNodeRepository;
import com.omninest.modules.file.repository.FileShareRecipientRepository;
import com.omninest.modules.photos.repository.PhotoAlbumFirstCoverProjection;
import com.omninest.modules.photos.repository.PhotoAlbumItemRepository;
import com.omninest.modules.photos.repository.PhotoGroupPreviewProjection;
import com.omninest.modules.photos.repository.PhotoItemRepository;
import com.omninest.modules.reader.domain.ReaderItem;
import com.omninest.modules.reader.repository.ReaderItemRepository;
import com.omninest.modules.video.domain.MediaWatchHistory;
import com.omninest.modules.video.repository.MediaWatchHistoryRepository;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.HexFormat;
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
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * 2026-10-22 审计新增/改写查询的真实数据库契约测试。
 *
 * <p>上下文冒烟只能证明 HQL 可解析，单测只碰 mock；分页过滤、countQuery、
 * EXISTS 权限、LIKE 转义、窗口函数与原生排序都必须在 PostgreSQL 上执行。
 * 每个用例使用独立随机用户，避免相互污染。</p>
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
                "omninest.search.index-path=${java.io.tmpdir}/omninest-audit-query-it"
        }
)
@ActiveProfiles("dev")
@Testcontainers(disabledWithoutDocker = true)
@Import(AuditQueryContractIT.ExternalDependencyOverrides.class)
class AuditQueryContractIT {

    private static final String IMAGE = "postgres:18-alpine";

    @Container
    private static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>(IMAGE)
            .withDatabaseName("omninest_audit_query_it")
            .withUsername("omninest")
            .withPassword("omninest");

    @Container
    private static final GenericContainer<?> REDIS = new GenericContainer<>("redis:8")
            .withExposedPorts(6379);

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @Autowired
    private FileShareRecipientRepository shareRecipientRepository;

    @Autowired
    private FileNodeRepository fileNodeRepository;

    @Autowired
    private ReaderItemRepository readerItemRepository;

    @Autowired
    private MediaWatchHistoryRepository historyRepository;

    @Autowired
    private PhotoAlbumItemRepository albumItemRepository;

    @Autowired
    private PhotoItemRepository photoItemRepository;

    @Autowired
    private ExternalStorageOAuthService oauthService;

    @DynamicPropertySource
    static void registerDatabaseProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", POSTGRES::getJdbcUrl);
        registry.add("spring.datasource.username", POSTGRES::getUsername);
        registry.add("spring.datasource.password", POSTGRES::getPassword);
        registry.add("spring.data.redis.host", REDIS::getHost);
        registry.add("spring.data.redis.port", () -> REDIS.getMappedPort(6379));
    }

    @Test
    @DisplayName("收到的分享分页在 SQL 层剔除撤销/过期/软删/易主，内容与总数一致")
    void sharedWithMePageFiltersBeforePaging() {
        UUID owner = UUID.randomUUID();
        UUID recipient = UUID.randomUUID();
        UUID otherOwner = UUID.randomUUID();

        UUID visibleNodeA = insertFileNode(owner, "/share/visible-a.pdf", false, "PERSONAL", false);
        UUID visibleNodeB = insertFileNode(owner, "/share/visible-b.pdf", false, "PERSONAL", false);
        UUID deletedNode = insertFileNode(owner, "/share/deleted.pdf", false, "PERSONAL", true);
        UUID foreignNode = insertFileNode(otherOwner, "/share/foreign.pdf", false, "PERSONAL", false);
        Instant now = Instant.now();

        insertRecipient(insertShare(owner, visibleNodeA, null, null), recipient, now.minusSeconds(5));
        insertRecipient(insertShare(owner, visibleNodeB, null, null), recipient, now.minusSeconds(4));
        insertRecipient(insertShare(owner, deletedNode, null, null), recipient, now.minusSeconds(3));
        insertRecipient(insertShare(owner, visibleNodeA, now.minusSeconds(1), null), recipient,
                now.minusSeconds(2));
        insertRecipient(insertShare(owner, visibleNodeA, null, now.minusSeconds(1)), recipient,
                now.minusSeconds(2));
        insertRecipient(insertShare(owner, foreignNode, null, null), recipient, now.minusSeconds(1));

        Page<FileShareRecipient> firstPage = shareRecipientRepository
                .findActiveVisibleByRecipientUserIdPage(recipient, PageRequest.of(0, 1));

        assertThat(firstPage.getTotalElements()).isEqualTo(2);
        assertThat(firstPage.getContent()).hasSize(1);
        assertThat(firstPage.getContent().getFirst().getShareLink().getResourceId()).isEqualTo(visibleNodeB);

        Page<FileShareRecipient> secondPage = shareRecipientRepository
                .findActiveVisibleByRecipientUserIdPage(recipient, PageRequest.of(1, 1));
        assertThat(secondPage.getTotalElements()).isEqualTo(2);
        assertThat(secondPage.getContent().getFirst().getShareLink().getResourceId()).isEqualTo(visibleNodeA);
    }

    @Test
    @DisplayName("共享文件可见性按用户覆盖优先于全局权限，并在 SQL 层过滤")
    void sharedFilesPageResolvesPermissionPrecedence() {
        UUID owner = UUID.randomUUID();
        UUID viewer = UUID.randomUUID();

        UUID globalAllowed = insertFileNode(owner, "/shared/global.pdf", true, "PERSONAL", false);
        UUID userDenied = insertFileNode(owner, "/shared/user-denied.pdf", true, "PERSONAL", false);
        UUID userAllowed = insertFileNode(owner, "/shared/user-allowed.pdf", true, "PERSONAL", false);
        UUID noPermission = insertFileNode(owner, "/shared/none.pdf", true, "PERSONAL", false);
        UUID notShared = insertFileNode(owner, "/shared/private.pdf", false, "PERSONAL", false);

        insertPermission(globalAllowed, null, true);
        insertPermission(userDenied, null, true);
        insertPermission(userDenied, viewer, false);
        insertPermission(userAllowed, null, false);
        insertPermission(userAllowed, viewer, true);
        // noPermission 不写任何权限行：与 resolvePermissions 的 denyAll 同口径
        insertPermission(notShared, null, true);

        Page<FileNode> page = fileNodeRepository.findSharedFilesVisiblePage(viewer, PageRequest.of(0, 10));

        assertThat(page.getTotalElements()).isEqualTo(2);
        assertThat(page.getContent()).extracting(FileNode::getId)
                .containsExactlyInAnyOrder(globalAllowed, userAllowed);
        assertThat(page.getContent()).extracting(FileNode::getId)
                .doesNotContain(userDenied, noPermission, notShared);
    }

    @Test
    @DisplayName("阅读器分页下推类型/关键词/书架过滤，LIKE 转义与 countQuery 同谓词")
    void readerItemsPagePushesFiltersAndEscapesLike() {
        UUID owner = UUID.randomUUID();
        UUID sharedOwner = UUID.randomUUID();

        UUID personalNode = insertFileNode(owner, "/reader/personal.epub", false, "PERSONAL", false);
        UUID sharedNode = insertFileNode(sharedOwner, "/reader/shared.epub", false, "SHARED", false);
        UUID deletedNode = insertFileNode(owner, "/reader/deleted.epub", false, "PERSONAL", true);
        UUID foreignPersonalNode = insertFileNode(sharedOwner, "/reader/foreign.epub", false, "PERSONAL", false);
        UUID shelfNode = insertFileNode(owner, "/reader/shelf.txt", false, "PERSONAL", false);
        UUID percentNode = insertFileNode(owner, "/reader/percent.txt", false, "PERSONAL", false);
        UUID similarNode = insertFileNode(owner, "/reader/similar.txt", false, "PERSONAL", false);

        insertReaderItem(owner, personalNode, "Personal Book", "Alice", "EPUB", "TEXT");
        insertReaderItem(sharedOwner, sharedNode, "Shared Book", "Bob", "EPUB", "TEXT");
        insertReaderItem(owner, deletedNode, "Deleted Book", "Alice", "EPUB", "TEXT");
        insertReaderItem(sharedOwner, foreignPersonalNode, "Foreign Personal", "Eve", "EPUB", "TEXT");
        UUID shelfItem = insertReaderItem(owner, shelfNode, "Shelf Book", "Carol", "TXT", "TEXT");
        insertReaderItem(owner, percentNode, "100% 完成", "Carol", "TXT", "TEXT");
        insertReaderItem(owner, similarNode, "100X 完成", "Carol", "TXT", "TEXT");
        insertBookshelf(owner, shelfItem);

        Page<ReaderItem> all = readerItemRepository.findVisibleItemsPage(
                owner, SpaceType.SHARED, "", "", "", false, PageRequest.of(0, 2));
        assertThat(all.getTotalElements()).isEqualTo(5);
        assertThat(all.getContent()).hasSize(2);

        Page<ReaderItem> escaped = readerItemRepository.findVisibleItemsPage(
                owner, SpaceType.SHARED, "", "", LikePatterns.escapeSpecials("100%"),
                false, PageRequest.of(0, 10));
        assertThat(escaped.getTotalElements()).isEqualTo(1);
        assertThat(escaped.getContent()).extracting(ReaderItem::getTitle).containsExactly("100% 完成");

        Page<ReaderItem> shelfOnly = readerItemRepository.findVisibleItemsPage(
                owner, SpaceType.SHARED, "", "", "", true, PageRequest.of(0, 10));
        assertThat(shelfOnly.getTotalElements()).isEqualTo(1);
        assertThat(shelfOnly.getContent().getFirst().getId()).isEqualTo(shelfItem);

        Page<ReaderItem> typed = readerItemRepository.findVisibleItemsPage(
                owner, SpaceType.SHARED, "TXT", "", "", false, PageRequest.of(0, 10));
        assertThat(typed.getTotalElements()).isEqualTo(3);
        assertThat(typed.getContent()).extracting(ReaderItem::getItemType).containsOnly("TXT");
    }

    @Test
    @DisplayName("系列观看历史按 owner 与 seriesId 精确过滤并倒序")
    void seriesHistoryFiltersAndOrders() {
        UUID viewer = UUID.randomUUID();
        UUID other = UUID.randomUUID();
        UUID seriesA = UUID.randomUUID();
        UUID seriesB = UUID.randomUUID();

        UUID episodeA1 = insertVideoItem(viewer, seriesA, "S01E01");
        UUID episodeA2 = insertVideoItem(viewer, seriesA, "S01E02");
        UUID episodeB1 = insertVideoItem(viewer, seriesB, "S02E01");

        insertHistory(viewer, episodeA1, Instant.parse("2026-05-01T10:00:00Z"));
        insertHistory(viewer, episodeA2, Instant.parse("2026-05-02T10:00:00Z"));
        insertHistory(viewer, episodeB1, Instant.parse("2026-05-03T10:00:00Z"));
        insertHistory(other, episodeA1, Instant.parse("2026-05-04T10:00:00Z"));

        List<MediaWatchHistory> history =
                historyRepository.findByOwnerUserIdAndSeriesIdOrderByPlayedAtDesc(viewer, seriesA);

        assertThat(history).extracting(MediaWatchHistory::getVideoItemId)
                .containsExactly(episodeA2, episodeA1);
    }

    @Test
    @DisplayName("相册首张有效照片封面由窗口函数一次批量返回")
    void albumFirstCoverBatchResolvesActiveSortOrder() {
        UUID owner = UUID.randomUUID();
        UUID album = UUID.randomUUID();
        UUID emptyAlbum = UUID.randomUUID();

        UUID firstNode = insertFileNode(owner, "/album/first.jpg", false, "PERSONAL", false);
        UUID secondNode = insertFileNode(owner, "/album/second.jpg", false, "PERSONAL", false);
        UUID trashedNode = insertFileNode(owner, "/album/trashed.jpg", false, "PERSONAL", true);
        UUID firstCover = UUID.randomUUID();
        UUID secondCover = UUID.randomUUID();

        UUID firstPhoto = insertPhotoItem(owner, firstNode, firstCover, null);
        UUID secondPhoto = insertPhotoItem(owner, secondNode, secondCover, null);
        UUID trashedPhoto = insertPhotoItem(owner, trashedNode, UUID.randomUUID(), null);

        insertAlbum(owner, album, "Album");
        insertAlbum(owner, emptyAlbum, "Empty");
        insertAlbumItem(owner, album, firstPhoto, 2);
        insertAlbumItem(owner, album, secondPhoto, 1);
        insertAlbumItem(owner, emptyAlbum, trashedPhoto, 0);

        Map<UUID, UUID> covers = albumItemRepository
                .findFirstActiveCoverFileIdsByAlbumIds(List.of(album, emptyAlbum))
                .stream()
                .collect(Collectors.toMap(
                        PhotoAlbumFirstCoverProjection::getAlbumId,
                        PhotoAlbumFirstCoverProjection::getCoverFileId
                ));

        assertThat(covers).containsOnlyKeys(album);
        assertThat(covers.get(album)).isEqualTo(secondCover);
    }

    @Test
    @DisplayName("照片分组按 DATE 时最新月份优先")
    void groupPreviewOrdersDateDescending() {
        UUID owner = UUID.randomUUID();
        insertPhotoForMonth(owner, "2025-01");
        insertPhotoForMonth(owner, "2025-02");
        insertPhotoForMonth(owner, "2025-03");

        List<PhotoGroupPreviewProjection> rows = photoItemRepository.findGroupPreviewPage(
                owner, "DATE", "UTC", 0, 10);

        List<String> keys = rows.stream()
                .map(PhotoGroupPreviewProjection::getGroupKey)
                .distinct()
                .toList();
        assertThat(keys).containsExactly("2025-03", "2025-02", "2025-01");
    }

    @Test
    @DisplayName("OAuth state 存 Redis 且一次性消费，providerCode 不一致时拒绝")
    void oauthStateIsConsumedFromRedisAndProviderMustMatch() {
        UUID owner = UUID.randomUUID();
        UUID accountId = UUID.randomUUID();
        String provider = "GDRIVE";
        jdbcTemplate.update("""
                INSERT INTO omni.storage_connector_oauth_apps
                    (id, connector_code, client_id, client_secret_encrypted, redirect_uri,
                     enabled, created_at, updated_at, version)
                VALUES (?, ?, 'client-id', 'encrypted-secret',
                        'http://localhost/api/v1/external-connectors/GDRIVE/oauth/callback',
                        true, now(), now(), 0)
                """, UUID.randomUUID(), provider);
        jdbcTemplate.update("""
                INSERT INTO omni.storage_external_accounts
                    (id, owner_user_id, provider, display_name, encrypted_credentials,
                     status, created_at, updated_at, version)
                VALUES (?, ?, ?, 'IT account', '{}', 'ACTIVE', now(), now(), 0)
                """, accountId, owner, provider);

        var issued = oauthService.start(owner, provider, accountId);

        assertThatThrownBy(
                        () -> oauthService.handleCallback("ONEDRIVE", issued.state(), "code"))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("不匹配");
        // state 已被原子取走：重复回调必须落到“失效”分支，而不是再次比对 provider。
        assertThatThrownBy(
                        () -> oauthService.handleCallback("ONEDRIVE", issued.state(), "code"))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("无效或已过期");
    }

    // ==================== 种子数据 ====================

    private UUID insertFileNode(
            UUID ownerUserId,
            String path,
            boolean shared,
            String spaceType,
            boolean deleted
    ) {
        UUID id = UUID.randomUUID();
        jdbcTemplate.update("""
                INSERT INTO omni.file_nodes
                    (id, owner_user_id, node_type, name, normalized_path, mime_type, size_bytes,
                     source_type, is_deleted, shared, space_type, created_at, updated_at, version)
                VALUES (?, ?, 'FILE', ?, ?, 'application/octet-stream', 1024, 'LOCAL', ?, ?, ?, now(), now(), 0)
                """, id, ownerUserId, path.substring(path.lastIndexOf('/') + 1), path, deleted, shared, spaceType);
        return id;
    }

    private UUID insertShare(UUID ownerUserId, UUID resourceId, Instant disabledAt, Instant expiresAt) {
        UUID id = UUID.randomUUID();
        jdbcTemplate.update("""
                INSERT INTO omni.share_links
                    (id, owner_user_id, resource_type, resource_id, token_hash, access_count,
                     include_location, original_quality, disabled_at, expires_at, created_at, updated_at, version)
                VALUES (?, ?, 'FILE', ?, ?, 0, true, true, ?, ?, now(), now(), 0)
                """, id, ownerUserId, resourceId, sha256(UUID.randomUUID().toString()),
                disabledAt == null ? null : Timestamp.from(disabledAt),
                expiresAt == null ? null : Timestamp.from(expiresAt));
        return id;
    }

    private void insertRecipient(UUID shareId, UUID recipientUserId, Instant createdAt) {
        jdbcTemplate.update("""
                INSERT INTO omni.file_share_recipients (id, share_link_id, recipient_user_id, created_at)
                VALUES (?, ?, ?, ?)
                """, UUID.randomUUID(), shareId, recipientUserId, Timestamp.from(createdAt));
    }

    private void insertPermission(UUID fileNodeId, UUID granteeUserId, boolean allowView) {
        jdbcTemplate.update("""
                INSERT INTO omni.file_node_permissions
                    (id, file_node_id, grantee_user_id, allow_view, allow_download,
                     allow_share, allow_edit, created_at, updated_at, version)
                VALUES (?, ?, ?, ?, true, false, false, now(), now(), 0)
                """, UUID.randomUUID(), fileNodeId, granteeUserId, allowView);
    }

    private UUID insertReaderItem(
            UUID ownerUserId,
            UUID fileNodeId,
            String title,
            String authorName,
            String itemType,
            String contentKind
    ) {
        UUID id = UUID.randomUUID();
        jdbcTemplate.update("""
                INSERT INTO omni.reader_items
                    (id, owner_user_id, file_node_id, item_type, title, author_name,
                     content_kind, created_at, updated_at, version)
                VALUES (?, ?, ?, ?, ?, ?, ?, now(), now(), 0)
                """, id, ownerUserId, fileNodeId, itemType, title, authorName, contentKind);
        return id;
    }

    private void insertBookshelf(UUID ownerUserId, UUID readerItemId) {
        jdbcTemplate.update("""
                INSERT INTO omni.reader_bookshelf (id, owner_user_id, reader_item_id, created_at)
                VALUES (?, ?, ?, now())
                """, UUID.randomUUID(), ownerUserId, readerItemId);
    }

    private UUID insertVideoItem(UUID ownerUserId, UUID seriesId, String versionLabel) {
        UUID id = UUID.randomUUID();
        UUID fileNodeId = insertFileNode(ownerUserId, "/video/" + id + ".mkv", false, "PERSONAL", false);
        jdbcTemplate.update("""
                INSERT INTO omni.media_video_items
                    (id, owner_user_id, file_node_id, media_type, series_id, version_label,
                     metadata_status, created_at, updated_at, version)
                VALUES (?, ?, ?, 'EPISODE', ?, ?, 'MATCHED', now(), now(), 0)
                """, id, ownerUserId, fileNodeId, seriesId, versionLabel);
        return id;
    }

    private void insertHistory(UUID ownerUserId, UUID videoItemId, Instant playedAt) {
        jdbcTemplate.update("""
                INSERT INTO omni.media_watch_history
                    (id, owner_user_id, video_item_id, position_seconds, duration_seconds,
                     completed, played_at, metadata, version)
                VALUES (?, ?, ?, 10, 100, false, ?, '{}'::jsonb, 0)
                """, UUID.randomUUID(), ownerUserId, videoItemId, Timestamp.from(playedAt));
    }

    private UUID insertPhotoItem(UUID ownerUserId, UUID fileNodeId, UUID coverFileId, Instant dateTaken) {
        UUID id = UUID.randomUUID();
        jdbcTemplate.update("""
                INSERT INTO omni.photo_items
                    (id, owner_user_id, file_node_id, title, date_taken, format, file_size,
                     cover_file_id, metadata_status, created_at, updated_at, version)
                VALUES (?, ?, ?, 'IT Photo', ?, 'jpg', 1024, ?, 'MATCHED', now(), now(), 0)
                """, id, ownerUserId, fileNodeId,
                dateTaken == null ? null : Timestamp.from(dateTaken), coverFileId);
        return id;
    }

    private void insertAlbum(UUID ownerUserId, UUID albumId, String name) {
        jdbcTemplate.update("""
                INSERT INTO omni.photo_albums
                    (id, owner_user_id, name, photo_count, created_at, updated_at, version)
                VALUES (?, ?, ?, 0, now(), now(), 0)
                """, albumId, ownerUserId, name);
    }

    private void insertAlbumItem(UUID ownerUserId, UUID albumId, UUID photoId, int sortOrder) {
        jdbcTemplate.update("""
                INSERT INTO omni.photo_album_items
                    (id, owner_user_id, album_id, photo_id, sort_order, created_at, version)
                VALUES (?, ?, ?, ?, ?, now(), 0)
                """, UUID.randomUUID(), ownerUserId, albumId, photoId, sortOrder);
    }

    private void insertPhotoForMonth(UUID ownerUserId, String month) {
        String path = "/timeline/" + month + "/" + UUID.randomUUID() + ".jpg";
        UUID nodeId = insertFileNode(ownerUserId, path, false, "PERSONAL", false);
        insertPhotoItem(ownerUserId, nodeId, UUID.randomUUID(), Instant.parse(month + "-15T12:00:00Z"));
    }

    private static String sha256(String value) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            return HexFormat.of().formatHex(digest.digest(value.getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException exception) {
            throw new IllegalStateException("SHA-256 不可用", exception);
        }
    }

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
