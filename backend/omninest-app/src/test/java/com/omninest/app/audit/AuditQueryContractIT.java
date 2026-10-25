package com.omninest.app.audit;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.omninest.OmniNestApplication;
import com.omninest.common.cache.ReadThroughCache;
import com.omninest.common.error.BusinessException;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.common.storage.ObjectStorageKey;
import com.omninest.common.util.LikePatterns;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.FilePurgeState;
import com.omninest.modules.file.domain.FileShareRecipient;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.event.FileNodesDeletedEvent;
import com.omninest.modules.file.event.FilePurgeRequestedEvent;
import com.omninest.modules.file.repository.FileAccessRecordRepository;
import com.omninest.modules.file.repository.FileNodeRepository;
import com.omninest.modules.file.repository.FileShareRecipientRepository;
import com.omninest.modules.file.repository.FileVersionRepository;
import com.omninest.modules.file.service.ExternalStorageOAuthService;
import com.omninest.modules.file.service.ExternalStorageOAuthTokenClient;
import com.omninest.modules.file.service.FileManagerService;
import com.omninest.modules.file.service.FileNodeRelationCleanupService;
import com.omninest.modules.file.service.FilePurgeStateService;
import com.omninest.modules.file.service.FileShareRecipientAccessService;
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
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.HexFormat;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.stream.Collectors;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
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
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronizationManager;
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
    private static final ExternalStorageOAuthTokenClient TOKEN_CLIENT =
            mock(ExternalStorageOAuthTokenClient.class);

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

    @Autowired
    private FileManagerService fileManagerService;

    @Autowired
    private FileAccessRecordRepository accessRecordRepository;

    @Autowired
    private FileVersionRepository fileVersionRepository;

    @Autowired
    private FileNodeRelationCleanupService relationCleanupService;

    @Autowired
    private FilePurgeStateService filePurgeStateService;

    @Autowired
    private FileShareRecipientAccessService shareRecipientAccessService;

    @Autowired
    private ReadThroughCache readThroughCache;

    @BeforeEach
    void resetTokenClient() {
        Mockito.reset(TOKEN_CLIENT);
    }

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

        // 共享空间关闭或角色无浏览权时传 null：只返回个人条目，countQuery 必须同谓词。
        Page<ReaderItem> personalOnly = readerItemRepository.findVisibleItemsPage(
                owner, null, "", "", "", false, PageRequest.of(0, 10));
        assertThat(personalOnly.getTotalElements()).isEqualTo(4);
        assertThat(personalOnly.getContent()).extracting(ReaderItem::getTitle)
                .doesNotContain("Shared Book");
        assertThat(readerItemRepository.countVisibleItems(owner, null)).isEqualTo(4);
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

    @Test
    @DisplayName("访问计数以唯一键原子累加，最近访问在 SQL 层排除共享与回收站节点")
    void accessUpsertAccumulatesAtomicallyAndRecentQueryFiltersScope() throws Exception {
        UUID owner = UUID.randomUUID();
        String suffix = UUID.randomUUID().toString();
        UUID personalId = insertFileNode(owner, "/recent/" + suffix + "/personal.bin",
                false, "PERSONAL", false);
        UUID sharedId = insertFileNode(UUID.randomUUID(), "/recent/" + suffix + "/shared.bin",
                false, "SHARED", false);
        UUID deletedId = insertFileNode(owner, "/recent/" + suffix + "/deleted.bin",
                false, "PERSONAL", true);

        int calls = 16;
        try (ExecutorService executor = Executors.newFixedThreadPool(8)) {
            List<Future<?>> futures = new ArrayList<>();
            for (int index = 0; index < calls; index++) {
                futures.add(executor.submit(() -> fileManagerService.recordAccess(owner, personalId)));
            }
            for (Future<?> future : futures) {
                future.get();
            }
        }

        Integer accessCount = jdbcTemplate.queryForObject("""
                SELECT access_count FROM omni.file_access_records
                WHERE owner_user_id = ? AND file_node_id = ?
                """, Integer.class, owner, personalId);
        Integer rowCount = jdbcTemplate.queryForObject("""
                SELECT count(*) FROM omni.file_access_records
                WHERE owner_user_id = ? AND file_node_id = ?
                """, Integer.class, owner, personalId);
        // 先查后改会在这 16 个并发请求里丢计数；唯一键冲突更新必须保留全部次数且只有一行。
        assertThat(accessCount).isEqualTo(calls);
        assertThat(rowCount).isEqualTo(1);

        jdbcTemplate.update("""
                INSERT INTO omni.file_access_records (owner_user_id, file_node_id)
                VALUES (?, ?)
                """, owner, sharedId);
        jdbcTemplate.update("""
                INSERT INTO omni.file_access_records (owner_user_id, file_node_id)
                VALUES (?, ?)
                """, owner, deletedId);

        List<FileNode> recent = accessRecordRepository.findRecentNodes(
                owner, SpaceType.PERSONAL, PageRequest.of(0, 50));

        // 共享空间访问不得挤占个人最近窗口，回收站节点也不能出现在结果里。
        assertThat(recent).extracting(FileNode::getId).containsExactly(personalId);
    }

    @Test
    @DisplayName("Purge 引用判定忽略已挂任务的节点与版本，零引用按全表计算")
    void purgeReferenceQueriesIgnorePurgeBoundRows() {
        UUID owner = UUID.randomUUID();
        UUID objectA = insertFileObject("/purge/" + UUID.randomUUID() + "/a.bin", 100L);
        UUID objectB = insertFileObject("/purge/" + UUID.randomUUID() + "/b.bin", 50L);
        UUID taskA = UUID.randomUUID();
        UUID taskB = UUID.randomUUID();
        UUID nodeA = insertFileNodeWithObject(owner, "/purge/a-" + UUID.randomUUID() + ".bin",
                objectA, taskA);
        UUID nodeB = insertFileNodeWithObject(owner, "/purge/b-" + UUID.randomUUID() + ".bin",
                objectA, null);
        insertVersionRow(nodeA, objectB, 1);

        assertThat(fileNodeRepository.findCurrentObjectIdsReferencedByUnpurgedNodes(List.of(objectA)))
                .containsExactly(objectA);
        // 另一个任务也进入删除流程后，两边都不能再把对方当作存活引用。
        jdbcTemplate.update("UPDATE omni.file_nodes SET purge_task_id = ? WHERE id = ?", taskB, nodeB);
        assertThat(fileNodeRepository.findCurrentObjectIdsReferencedByUnpurgedNodes(List.of(objectA)))
                .isEmpty();
        // 行清理必须看全表引用，不能因为节点已挂任务就提前删除 file_objects。
        assertThat(fileNodeRepository.findCurrentObjectIdsInUse(List.of(objectA)))
                .containsExactly(objectA);

        assertThat(fileVersionRepository.findObjectIdsReferencedByUnpurgedNodes(List.of(objectB)))
                .isEmpty();
        jdbcTemplate.update("UPDATE omni.file_nodes SET purge_task_id = NULL WHERE id = ?", nodeA);
        assertThat(fileVersionRepository.findObjectIdsReferencedByUnpurgedNodes(List.of(objectB)))
                .containsExactly(objectB);
        assertThat(fileVersionRepository.findObjectIdsInUse(List.of(objectB)))
                .containsExactly(objectB);
    }

    @Test
    @DisplayName("永久删除收尾跨批次删对象行，并按第二个批次仍可见的对象大小释放版本配额")
    void purgeFinalizationDeletesObjectsAfterAllBatches() {
        UUID owner = UUID.randomUUID();
        UUID taskId = UUID.randomUUID();
        jdbcTemplate.update("""
                INSERT INTO omni.auth_users (id, username, password_hash, used_bytes)
                VALUES (?, ?, 'it-hash', 100000)
                """, owner, "purge-" + owner);
        jdbcTemplate.update("""
                INSERT INTO omni.sys_tasks
                    (id, task_type, status, owner_user_id, created_at, updated_at, version)
                VALUES (?, 'FILE_PURGE', 'RUNNING', ?, now(), now(), 0)
                """, taskId, owner);
        UUID currentObject = insertFileObject("/purge/batch/current-" + UUID.randomUUID(), 100L);
        UUID versionObject = insertFileObject("/purge/batch/version-" + UUID.randomUUID(), 50L);
        List<UUID> nodeIds = insertPurgeNodes(owner, taskId, currentObject, 501);
        insertVersionRow(nodeIds.getLast(), versionObject, 1);

        filePurgeStateService.finalizePurge(
                new FilePurgeRequestedEvent(taskId, owner, nodeIds.getFirst()));

        assertThat(count("SELECT count(*) FROM omni.file_nodes WHERE purge_task_id = ?", taskId))
                .isZero();
        assertThat(count("SELECT count(*) FROM omni.file_objects WHERE id IN (?, ?)",
                currentObject, versionObject)).isZero();
        assertThat(count("SELECT count(*) FROM omni.file_versions WHERE object_id = ?", versionObject))
                .isZero();
        // 501 个文件各计 100 字节，加第二个批次的历史版本 50 字节；首批提前删对象行时会漏掉版本字节。
        assertThat(jdbcTemplate.queryForObject(
                "SELECT used_bytes FROM omni.auth_users WHERE id = ?", Long.class, owner))
                .isEqualTo(49_850L);
        Map<String, Object> task = jdbcTemplate.queryForMap(
                "SELECT status, result FROM omni.sys_tasks WHERE id = ?", taskId);
        assertThat(task.get("status")).isEqualTo("COMPLETED");
        assertThat(task.get("result").toString())
                .contains("\"releasedBytes\":50150")
                .contains("\"fileNodeCount\":501")
                .contains("\"deletedObjectRowCount\":2");
    }

    @Test
    @DisplayName("跨空间移动的子树查询包含回收站后代且按精确路径前缀限定")
    void moveSubtreeQueriesIncludeDeletedDescendantsWithinExactPrefix() {
        UUID owner = UUID.randomUUID();
        UUID other = UUID.randomUUID();
        String sharedBase = "/move-" + UUID.randomUUID();
        UUID activeChild = insertFileNode(other, sharedBase + "/active.txt", false, "SHARED", false);
        UUID deletedChild = insertFileNode(owner, sharedBase + "/deleted.txt", false, "SHARED", true);
        insertFileNode(owner, sharedBase + "X/outside.txt", false, "SHARED", false);

        List<FileNode> sharedSubtree = fileNodeRepository.findSubtreeInSpaceIncludingDeleted(
                SpaceType.SHARED, LikePatterns.escapeSpecials(sharedBase + "/"));

        assertThat(sharedSubtree).extracting(FileNode::getId)
                .containsExactlyInAnyOrder(activeChild, deletedChild);

        String personalBase = "/pmove-" + UUID.randomUUID();
        UUID activePersonal = insertFileNode(owner, personalBase + "/active.txt",
                false, "PERSONAL", false);
        UUID deletedPersonal = insertFileNode(owner, personalBase + "/deleted.txt",
                false, "PERSONAL", true);
        insertFileNode(other, personalBase + "/other.txt", false, "PERSONAL", false);

        List<FileNode> personalSubtree = fileNodeRepository.findPersonalSubtreeIncludingDeleted(
                owner, SpaceType.PERSONAL, LikePatterns.escapeSpecials(personalBase + "/"));

        assertThat(personalSubtree).extracting(FileNode::getId)
                .containsExactlyInAnyOrder(activePersonal, deletedPersonal);
    }

    @Test
    @DisplayName("物理删除清理所有用户的访问/收藏/分享链接并驱逐分享缓存")
    void physicalDeleteCleanupRemovesCrossUserRelationsAndCache() {
        UUID owner = UUID.randomUUID();
        UUID viewer = UUID.randomUUID();
        UUID nodeId = UUID.randomUUID();
        for (UUID userId : List.of(owner, viewer)) {
            jdbcTemplate.update("""
                    INSERT INTO omni.file_access_records (owner_user_id, file_node_id)
                    VALUES (?, ?)
                    """, userId, nodeId);
            jdbcTemplate.update("""
                    INSERT INTO omni.file_favorites (owner_user_id, file_node_id)
                    VALUES (?, ?)
                    """, userId, nodeId);
        }
        String tokenHash = sha256(UUID.randomUUID().toString());
        jdbcTemplate.update("""
                INSERT INTO omni.share_links (owner_user_id, resource_type, resource_id, token_hash)
                VALUES (?, 'FILE', ?, ?)
                """, viewer, nodeId, tokenHash);
        String cacheKey = "omninest:share:link:" + tokenHash;
        readThroughCache.getOrLoad(cacheKey, Duration.ofMinutes(5), () -> "cached", String.class);
        assertThat(readThroughCache.take(cacheKey)).isNotNull();
        readThroughCache.getOrLoad(cacheKey, Duration.ofMinutes(5), () -> "cached", String.class);

        relationCleanupService.handleFileNodesDeleted(
                new FileNodesDeletedEvent(owner, List.of(nodeId), Instant.now()));

        assertThat(count("SELECT count(*) FROM omni.file_access_records WHERE file_node_id = ?", nodeId))
                .isZero();
        assertThat(count("SELECT count(*) FROM omni.file_favorites WHERE file_node_id = ?", nodeId))
                .isZero();
        assertThat(count("SELECT count(*) FROM omni.share_links WHERE resource_id = ?", nodeId))
                .isZero();
        assertThat(readThroughCache.take(cacheKey)).isNull();
    }

    @Test
    @DisplayName("V001 补齐的 UUID/时间默认值在原生插入时生效")
    void baselineDefaultsGenerateIdsAndTimestamps() {
        UUID owner = UUID.randomUUID();
        UUID importTaskId = jdbcTemplate.queryForObject("""
                INSERT INTO omni.storage_import_tasks
                    (owner_user_id, external_account_id, source_path, file_name)
                VALUES (?, ?, '/source', 'file.bin')
                RETURNING id
                """, UUID.class, owner, UUID.randomUUID());
        UUID metadataCacheId = jdbcTemplate.queryForObject("""
                INSERT INTO omni.storage_remote_metadata_cache
                    (external_account_id, remote_path, metadata_json, expires_at)
                VALUES (?, '/remote', '{}'::jsonb, now())
                RETURNING id
                """, UUID.class, UUID.randomUUID());
        UUID checkpointId = jdbcTemplate.queryForObject("""
                INSERT INTO omni.sync_event_checkpoints (checkpoint_key)
                VALUES (?)
                RETURNING id
                """, UUID.class, "it-" + UUID.randomUUID());
        Timestamp preferenceCreatedAt = jdbcTemplate.queryForObject("""
                INSERT INTO omni.user_preferences (owner_user_id, scope)
                VALUES (?, 'it')
                RETURNING created_at
                """, Timestamp.class, owner);

        assertThat(importTaskId).isNotNull();
        assertThat(metadataCacheId).isNotNull();
        assertThat(checkpointId).isNotNull();
        assertThat(preferenceCreatedAt).isNotNull();
    }

    @Test
    @DisplayName("OAuth 令牌交换发生在数据库事务之外，随后由短事务落库")
    void oauthTokenExchangeRunsOutsideDatabaseTransaction() {
        UUID owner = UUID.randomUUID();
        UUID accountId = UUID.randomUUID();
        String provider = "DROPBOX";
        jdbcTemplate.update("""
                INSERT INTO omni.storage_connector_oauth_apps
                    (id, connector_code, client_id, client_secret_encrypted, redirect_uri,
                     enabled, created_at, updated_at, version)
                VALUES (?, ?, 'client-id', 'encrypted-secret',
                        'http://localhost/api/v1/external-connectors/DROPBOX/oauth/callback',
                        true, now(), now(), 0)
                """, UUID.randomUUID(), provider);
        jdbcTemplate.update("""
                INSERT INTO omni.storage_external_accounts
                    (id, owner_user_id, provider, display_name, encrypted_credentials,
                     status, created_at, updated_at, version)
                VALUES (?, ?, ?, 'IT oauth account', '{}', 'ACTIVE', now(), now(), 0)
                """, accountId, owner, provider);

        var issued = oauthService.start(owner, provider, accountId);
        when(TOKEN_CLIENT.exchangeCode(eq(provider), any(), eq("authorization-code")))
                .thenAnswer(invocation -> {
                    // 外部 HTTP 最长 30 秒，若仍在数据库事务里，慢回调会耗尽 Hikari 连接。
                    assertThat(TransactionSynchronizationManager.isActualTransactionActive())
                            .isFalse();
                    return Map.of(
                            "access_token", "at",
                            "refresh_token", "rt",
                            "expires_in", 3600
                    );
                });

        oauthService.handleCallback(provider, issued.state(), "authorization-code");

        Map<String, Object> stored = jdbcTemplate.queryForMap("""
                SELECT status, encrypted_credentials FROM omni.storage_external_accounts
                WHERE id = ?
                """, accountId);
        assertThat(stored.get("status")).isEqualTo("ACTIVE");
        assertThat(stored.get("encrypted_credentials")).isNotEqualTo("{}");
    }

    @Test
    @Transactional
    @DisplayName("共享贡献节点按空间挂到任务，不要求属于同一上传者")
    void sharedContributionAssignmentIgnoresOwner() {
        UUID firstNode = insertFileNode(UUID.randomUUID(),
                "/contribution/first-" + UUID.randomUUID() + ".jpg", false, "SHARED", false);
        UUID secondNode = insertFileNode(UUID.randomUUID(),
                "/contribution/second-" + UUID.randomUUID() + ".jpg", false, "SHARED", false);
        UUID taskId = UUID.randomUUID();
        UUID operator = UUID.randomUUID();

        int updated = fileNodeRepository.assignSharedIdsToPurge(
                List.of(firstNode, secondNode), taskId, operator,
                FilePurgeState.RUNNING, Instant.now());

        assertThat(updated).isEqualTo(2);
        assertThat(count("SELECT count(*) FROM omni.file_nodes "
                + "WHERE purge_task_id = ? AND is_deleted = true", taskId)).isEqualTo(2);
    }

    @Test
    @DisplayName("定向分享接收关系在真库上覆盖单文件、文件夹后代，排除过期与兄弟前缀")
    void recipientAccessQueriesCoverFileAndFolderShares() {
        UUID owner = UUID.randomUUID();
        UUID recipient = UUID.randomUUID();
        UUID directFile = insertFileNode(owner, "/recipient/direct.txt", false, "PERSONAL", false);
        String folderPath = "/recipient/folder-" + UUID.randomUUID();
        UUID folderNode = insertFileNode(owner, folderPath, false, "PERSONAL", false);
        UUID childNode = insertFileNode(owner, folderPath + "/child.txt", false, "PERSONAL", false);
        UUID siblingNode = insertFileNode(owner, folderPath + "X/sibling.txt", false, "PERSONAL", false);
        UUID expiredNode = insertFileNode(owner, "/recipient/expired.txt", false, "PERSONAL", false);

        Instant now = Instant.now();
        insertRecipient(insertShare(owner, directFile, "FILE", null, null), recipient, now);
        insertRecipient(insertShare(owner, folderNode, "FOLDER", null, null), recipient, now);
        insertRecipient(insertShare(owner, expiredNode, "FILE", null, now.minusSeconds(60)), recipient, now);

        assertThat(shareRecipientAccessService.canAccessRecipientNode(
                recipient, requireNode(directFile))).isTrue();
        assertThat(shareRecipientAccessService.canAccessRecipientNode(
                recipient, requireNode(childNode))).isTrue();
        assertThat(shareRecipientAccessService.canAccessRecipientNode(
                recipient, requireNode(siblingNode))).isFalse();
        assertThat(shareRecipientAccessService.canAccessRecipientNode(
                recipient, requireNode(expiredNode))).isFalse();
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
        return insertShare(ownerUserId, resourceId, "FILE", disabledAt, expiresAt);
    }

    private UUID insertShare(
            UUID ownerUserId,
            UUID resourceId,
            String resourceType,
            Instant disabledAt,
            Instant expiresAt
    ) {
        UUID id = UUID.randomUUID();
        jdbcTemplate.update("""
                INSERT INTO omni.share_links
                    (id, owner_user_id, resource_type, resource_id, token_hash, access_count,
                     include_location, original_quality, disabled_at, expires_at, created_at, updated_at, version)
                VALUES (?, ?, ?, ?, ?, 0, true, true, ?, ?, now(), now(), 0)
                """, id, ownerUserId, resourceType, resourceId, sha256(UUID.randomUUID().toString()),
                disabledAt == null ? null : Timestamp.from(disabledAt),
                expiresAt == null ? null : Timestamp.from(expiresAt));
        return id;
    }

    private FileNode requireNode(UUID nodeId) {
        return fileNodeRepository.findByIdAndDeletedFalse(nodeId)
                .orElseThrow(() -> new IllegalStateException("测试节点不存在: " + nodeId));
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

    private UUID insertFileObject(String objectKey, long sizeBytes) {
        UUID objectId = UUID.randomUUID();
        jdbcTemplate.update("""
                INSERT INTO omni.file_objects
                    (id, bucket_name, object_key, size_bytes, created_at, updated_at, version)
                VALUES (?, 'user-files', ?, ?, now(), now(), 0)
                """, objectId, objectKey, sizeBytes);
        return objectId;
    }

    private List<UUID> insertPurgeNodes(
            UUID ownerUserId,
            UUID purgeTaskId,
            UUID objectId,
            int nodeCount
    ) {
        List<UUID> nodeIds = new ArrayList<>(nodeCount);
        List<Object[]> rows = new ArrayList<>(nodeCount);
        String prefix = "/purge/batch-" + UUID.randomUUID() + "/";
        for (int index = 0; index < nodeCount; index++) {
            UUID nodeId = UUID.randomUUID();
            nodeIds.add(nodeId);
            rows.add(new Object[]{nodeId, ownerUserId, "f" + index + ".bin", prefix + "f" + index + ".bin",
                    objectId, purgeTaskId});
        }
        jdbcTemplate.batchUpdate("""
                INSERT INTO omni.file_nodes
                    (id, owner_user_id, node_type, name, normalized_path, mime_type, size_bytes,
                     current_object_id, is_deleted, space_type, purge_state, purge_task_id,
                     created_at, updated_at, version)
                VALUES (?, ?, 'FILE', ?, ?, 'application/octet-stream', 100,
                        ?, true, 'PERSONAL', 'RUNNING', ?, now(), now(), 0)
                """, rows);
        return nodeIds;
    }

    private UUID insertFileNodeWithObject(
            UUID ownerUserId,
            String path,
            UUID objectId,
            UUID purgeTaskId
    ) {
        UUID nodeId = UUID.randomUUID();
        jdbcTemplate.update("""
                INSERT INTO omni.file_nodes
                    (id, owner_user_id, node_type, name, normalized_path, mime_type, size_bytes,
                     current_object_id, is_deleted, space_type, purge_task_id,
                     created_at, updated_at, version)
                VALUES (?, ?, 'FILE', ?, ?, 'application/octet-stream', 1024,
                        ?, false, 'PERSONAL', ?, now(), now(), 0)
                """, nodeId, ownerUserId, path.substring(path.lastIndexOf('/') + 1),
                path, objectId, purgeTaskId);
        return nodeId;
    }

    private void insertVersionRow(UUID nodeId, UUID objectId, int versionNo) {
        jdbcTemplate.update("""
                INSERT INTO omni.file_versions
                    (id, file_node_id, object_id, version_no, change_type, created_at, version)
                VALUES (?, ?, ?, ?, 'EDIT', now(), 0)
                """, UUID.randomUUID(), nodeId, objectId, versionNo);
    }

    private int count(String sql, Object... args) {
        Integer value = jdbcTemplate.queryForObject(sql, Integer.class, args);
        return value == null ? 0 : value;
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
        @Primary
        ExternalStorageOAuthTokenClient tokenClient() {
            return TOKEN_CLIENT;
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
