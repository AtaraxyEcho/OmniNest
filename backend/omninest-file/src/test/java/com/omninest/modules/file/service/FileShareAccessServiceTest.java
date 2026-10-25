package com.omninest.modules.file.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.cache.ReadThroughCache;
import com.omninest.common.error.BusinessException;
import com.omninest.common.ratelimit.RateLimitService;
import com.omninest.common.sync.UserSyncEventRecorder;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.NodeType;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.domain.ShareLink;
import com.omninest.modules.file.dto.FileDownloadUrlDto;
import com.omninest.modules.file.dto.FileNodeDto;
import com.omninest.modules.file.dto.AcceptShareRequest;
import com.omninest.modules.file.dto.FileShareChildDto;
import com.omninest.modules.file.dto.ShareAccessSessionDto;
import com.omninest.modules.file.repository.FileNodeRepository;
import com.omninest.modules.file.repository.FileShareRecipientRepository;
import com.omninest.modules.file.repository.ShareLinkRepository;
import com.omninest.modules.notification.port.NotificationPublisher;
import com.omninest.modules.quota.service.StorageQuotaService;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.Mockito;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageImpl;
import org.springframework.security.crypto.password.PasswordEncoder;

/**
 * FileShareAccessService 分享文件夹浏览的单元测试。
 *
 * @author OmniNest
 */
class FileShareAccessServiceTest {

    private static final UUID OWNER = UUID.fromString("20000000-0000-0000-0000-000000000001");
    private static final UUID SHARE_ID = UUID.fromString("20000000-0000-0000-0000-000000000002");
    private static final UUID ROOT_ID = UUID.fromString("20000000-0000-0000-0000-000000000003");
    private static final UUID SIBLING_ID = UUID.fromString("20000000-0000-0000-0000-000000000004");
    private static final UUID FILE_ID = UUID.fromString("20000000-0000-0000-0000-000000000005");
    private static final UUID SUB_FOLDER_ID = UUID.fromString("20000000-0000-0000-0000-000000000006");
    private static final UUID RECIPIENT = UUID.fromString("20000000-0000-0000-0000-000000000007");
    private static final String TOKEN = "plain-share-token";
    private static final String TOKEN_HASH = FileShareService.sha256(TOKEN);
    private static final String SESSION = "share-session-token";

    private final FileNodeRepository fileNodeRepository = Mockito.mock(FileNodeRepository.class);
    private final ShareLinkRepository shareLinkRepository = Mockito.mock(ShareLinkRepository.class);
    private final FileShareRecipientRepository shareRecipientRepository =
            Mockito.mock(FileShareRecipientRepository.class);
    private final PasswordEncoder passwordEncoder = Mockito.mock(PasswordEncoder.class);
    private final RateLimitService rateLimitService = Mockito.mock(RateLimitService.class);
    private final NotificationPublisher notificationService = Mockito.mock(NotificationPublisher.class);
    private final FileQueryService fileQueryService = Mockito.mock(FileQueryService.class);
    private final ResourceShareLinkService resourceShareLinkService =
            Mockito.mock(ResourceShareLinkService.class);
    private final ReadThroughCache readThroughCache = Mockito.mock(ReadThroughCache.class);
    private final FileNodeSupport fileNodeSupport = Mockito.mock(FileNodeSupport.class);
    private final StorageQuotaService storageQuotaService = Mockito.mock(StorageQuotaService.class);
    private final UserSyncEventRecorder syncEventRecorder = Mockito.mock(UserSyncEventRecorder.class);

    private final FileShareAccessService service = new FileShareAccessService(
            fileNodeRepository, shareLinkRepository, shareRecipientRepository, passwordEncoder,
            rateLimitService, notificationService,
            fileQueryService, resourceShareLinkService, readThroughCache, fileNodeSupport, storageQuotaService,
            syncEventRecorder, Mockito.mock(FileIndexSyncService.class)
    );

    @BeforeEach
    void setUpShareLookup() {
        Mockito.when(rateLimitService.tryAcquire(anyString(), Mockito.anyInt(), any(Duration.class)))
                .thenReturn(true);
        Mockito.when(readThroughCache.getOrLoad(anyString(), any(Duration.class), any(), eq(ShareLink.class)))
                .thenAnswer(invocation -> invocation.<java.util.function.Supplier<ShareLink>>getArgument(2).get());
        Mockito.when(shareLinkRepository.findByTokenHash(TOKEN_HASH))
                .thenReturn(Optional.of(share(NodeType.FOLDER.getValue())));
        Mockito.when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(ROOT_ID, OWNER))
                .thenReturn(Optional.of(node(ROOT_ID, "/docs", NodeType.FOLDER)));
    }

    @Test
    void childrenListingStaysInsideTheSharedSubtree() {
        // 兄弟目录必须与分享根同名前缀：/documentation 那种"看着像"的写法根本不构成威胁，
        // 只有 /docs-backup 才检验得出前缀判定带没带尾斜杠。
        Mockito.when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(SIBLING_ID, OWNER))
                .thenReturn(Optional.of(node(SIBLING_ID, "/docs-backup", NodeType.FOLDER)));

        assertThatThrownBy(() -> service.shareChildrenSession(TOKEN, SESSION, null, SIBLING_ID, 0, 50))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("不存在");

        Mockito.verifyNoInteractions(fileQueryService);
    }

    @Test
    void childrenListingAllowsNestedFolderInsideTheShare() {
        Mockito.when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(SUB_FOLDER_ID, OWNER))
                .thenReturn(Optional.of(node(SUB_FOLDER_ID, "/docs/nested", NodeType.FOLDER)));
        Mockito.when(fileQueryService.listFilesPage(OWNER, SUB_FOLDER_ID, null, 0, 50))
                .thenReturn(new PageImpl<>(List.of()));

        Page<FileShareChildDto> page = service.shareChildrenSession(
                TOKEN, SESSION, null, SUB_FOLDER_ID, 0, 50);

        assertThat(page.getContent()).isEmpty();
        Mockito.verify(fileQueryService).listFilesPage(OWNER, SUB_FOLDER_ID, null, 0, 50);
    }

    @Test
    void childrenListingRefusesAFileAsADirectoryToBrowse() {
        Mockito.when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(FILE_ID, OWNER))
                .thenReturn(Optional.of(node(FILE_ID, "/docs/a.mkv", NodeType.FILE)));

        assertThatThrownBy(() -> service.shareChildrenSession(TOKEN, SESSION, null, FILE_ID, 0, 50))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("没有子目录");

        Mockito.verifyNoInteractions(fileQueryService);
    }

    @Test
    void childrenListingRefusesAShareThatPointsAtASingleFile() {
        Mockito.when(shareLinkRepository.findByTokenHash(TOKEN_HASH))
                .thenReturn(Optional.of(share(NodeType.FILE.getValue())));

        assertThatThrownBy(() -> service.shareChildrenSession(TOKEN, SESSION, null, null, 0, 50))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("不是文件夹");

        Mockito.verifyNoInteractions(fileQueryService);
    }

    @Test
    void childrenListingSignsDownloadUrlsOnlyForFiles() {
        Mockito.when(fileQueryService.listFilesPage(OWNER, ROOT_ID, null, 0, 50))
                .thenReturn(new PageImpl<>(List.of(
                        childDto(FILE_ID, "a.mkv", NodeType.FILE),
                        childDto(SUB_FOLDER_ID, "nested", NodeType.FOLDER))));
        Mockito.when(fileQueryService.createDownloadUrls(eq(OWNER), any()))
                .thenReturn(Map.of(FILE_ID,
                        new FileDownloadUrlDto(FILE_ID, "a.mkv", "https://signed/a.mkv", Instant.now())));

        Page<FileShareChildDto> page = service.shareChildrenSession(TOKEN, SESSION, null, null, 0, 50);

        assertThat(page.getContent()).extracting(FileShareChildDto::name)
                .containsExactly("a.mkv", "nested");
        assertThat(page.getContent()).extracting(FileShareChildDto::downloadUrl)
                .containsExactly("https://signed/a.mkv", null);
        // 内部规范化路径不进分享响应：访客只需要目录名与层级标识。
        assertThat(page.getContent()).allSatisfy(child ->
                assertThat(child.toString()).doesNotContain("/docs/"));
    }

    @Test
    void recipientBrowsingRequiresTheRecipientRelationship() {
        Mockito.when(shareRecipientRepository.existsByShareLink_IdAndRecipientUserId(SHARE_ID, RECIPIENT))
                .thenReturn(false);

        assertThatThrownBy(() -> service.shareChildrenForRecipient(RECIPIENT, SHARE_ID, null, 0, 50))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("不是分享给你的");

        // 关系不在，连分享链接都不该去读，更不该列出任何子项。
        Mockito.verifyNoInteractions(fileQueryService);
        Mockito.verify(shareLinkRepository, Mockito.never()).findById(Mockito.any());
    }

    @Test
    void recipientBrowsingRefusesRevokedAndExpiredShares() {
        Mockito.when(shareRecipientRepository.existsByShareLink_IdAndRecipientUserId(SHARE_ID, RECIPIENT))
                .thenReturn(true);
        ShareLink revoked = share(NodeType.FOLDER.getValue());
        revoked.setDisabledAt(Instant.now().minusSeconds(60));
        Mockito.when(shareLinkRepository.findById(SHARE_ID)).thenReturn(Optional.of(revoked));

        assertThatThrownBy(() -> service.shareChildrenForRecipient(RECIPIENT, SHARE_ID, null, 0, 50))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("已撤销");

        ShareLink expired = share(NodeType.FOLDER.getValue());
        expired.setExpiresAt(Instant.now().minusSeconds(60));
        Mockito.when(shareLinkRepository.findById(SHARE_ID)).thenReturn(Optional.of(expired));

        assertThatThrownBy(() -> service.shareChildrenForRecipient(RECIPIENT, SHARE_ID, null, 0, 50))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("已过期");

        Mockito.verifyNoInteractions(fileQueryService);
    }

    /**
     * 定向侧必须复用同一道子树闸门：两条入口共用一份实现，越界判定不能各写一遍。
     */
    @Test
    void recipientBrowsingAppliesTheSameSubtreeGate() {
        Mockito.when(shareRecipientRepository.existsByShareLink_IdAndRecipientUserId(SHARE_ID, RECIPIENT))
                .thenReturn(true);
        Mockito.when(shareLinkRepository.findById(SHARE_ID))
                .thenReturn(Optional.of(share(NodeType.FOLDER.getValue())));
        Mockito.when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(SIBLING_ID, OWNER))
                .thenReturn(Optional.of(node(SIBLING_ID, "/docs-backup", NodeType.FOLDER)));

        assertThatThrownBy(() -> service.shareChildrenForRecipient(
                RECIPIENT, SHARE_ID, SIBLING_ID, 0, 50))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("不存在");

        Mockito.verifyNoInteractions(fileQueryService);
    }

    @Test
    void recipientBrowsingListsChildrenOfTheSharedFolder() {
        Mockito.when(shareRecipientRepository.existsByShareLink_IdAndRecipientUserId(SHARE_ID, RECIPIENT))
                .thenReturn(true);
        Mockito.when(shareLinkRepository.findById(SHARE_ID))
                .thenReturn(Optional.of(share(NodeType.FOLDER.getValue())));
        Mockito.when(fileQueryService.listFilesPage(OWNER, ROOT_ID, null, 0, 50))
                .thenReturn(new PageImpl<>(List.of(childDto(FILE_ID, "a.mkv", NodeType.FILE))));
        Mockito.when(fileQueryService.createDownloadUrls(eq(OWNER), any()))
                .thenReturn(Map.of(FILE_ID,
                        new FileDownloadUrlDto(FILE_ID, "a.mkv", "https://signed/a.mkv", Instant.now())));

        Page<FileShareChildDto> page = service.shareChildrenForRecipient(RECIPIENT, SHARE_ID, null, 0, 50);

        assertThat(page.getContent()).extracting(FileShareChildDto::downloadUrl)
                .containsExactly("https://signed/a.mkv");
    }

    @Test
    void issuingFileShareSessionConsumesAccessCountAtSessionCreation() {
        var issued = new ShareAccessSessionDto(
                SESSION, Instant.now().plusSeconds(600));
        Mockito.when(resourceShareLinkService.issueConsumedSession(TOKEN, "pw", null, "1.2.3.4"))
                .thenReturn(issued);

        var result = service.issueShareSession(TOKEN, "pw", "1.2.3.4");

        assertThat(result).isSameAs(issued);
        Mockito.verify(resourceShareLinkService).issueConsumedSession(TOKEN, "pw", null, "1.2.3.4");
        // 会话式入口是实际在用的分享访问路径，必须由它触发访问通知。
        Mockito.verify(notificationService).notifyOrLog(
                eq(OWNER), eq("SHARE_ACCESSED"), anyString(), anyString(), any());
    }

    @Test
    void acceptFolderShareSkipsDescendantsWhoseParentIsNotCopied() {
        when(shareLinkRepository.consumeAccess(eq(SHARE_ID), any(Instant.class))).thenReturn(1);
        when(shareLinkRepository.findById(SHARE_ID))
                .thenReturn(Optional.of(share(NodeType.FOLDER.getValue())));
        FileNode orphan = node(UUID.randomUUID(), "/docs/sub/report.pdf", NodeType.FILE);
        when(fileNodeRepository.findDescendantsByPrefixOrdered(
                OWNER, SpaceType.PERSONAL, "/docs/")).thenReturn(List.of(orphan));
        when(fileNodeRepository.saveAll(Mockito.anyList()))
                .thenAnswer(invocation -> invocation.getArgument(0));

        service.acceptShare(RECIPIENT, TOKEN, new AcceptShareRequest(null, null));

        ArgumentCaptor<List<FileNode>> saved = ArgumentCaptor.forClass(List.class);
        verify(fileNodeRepository).saveAll(saved.capture());
        assertThat(saved.getValue()).hasSize(1);
        assertThat(saved.getValue().getFirst().getName()).isEqualTo("docs");
    }

    @Test
    void acceptFolderShareRejectsSharedSpaceFolder() {
        when(shareLinkRepository.consumeAccess(eq(SHARE_ID), any(Instant.class))).thenReturn(1);
        when(shareLinkRepository.findById(SHARE_ID))
                .thenReturn(Optional.of(share(NodeType.FOLDER.getValue())));
        FileNode sharedFolder = node(ROOT_ID, "/docs", NodeType.FOLDER);
        sharedFolder.setSpaceType(SpaceType.SHARED);
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(ROOT_ID, OWNER))
                .thenReturn(Optional.of(sharedFolder));

        assertThatThrownBy(() -> service.acceptShare(
                RECIPIENT, TOKEN, new AcceptShareRequest(null, null)))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("共享空间文件夹");
        verify(fileNodeRepository, Mockito.never()).saveAll(Mockito.anyList());
    }

    private ShareLink share(String resourceType) {
        ShareLink link = new ShareLink();
        link.setId(SHARE_ID);
        link.setOwnerUserId(OWNER);
        link.setResourceType(resourceType);
        link.setResourceId(ROOT_ID);
        link.setTokenHash(TOKEN_HASH);
        return link;
    }

    private FileNode node(UUID id, String normalizedPath, NodeType nodeType) {
        FileNode node = new FileNode();
        node.setId(id);
        node.setOwnerUserId(OWNER);
        node.setNormalizedPath(normalizedPath);
        node.setNodeType(nodeType.getValue());
        node.setName(normalizedPath.substring(normalizedPath.lastIndexOf('/') + 1));
        return node;
    }

    private FileNodeDto childDto(UUID id, String name, NodeType nodeType) {
        return new FileNodeDto(
                id, ROOT_ID, nodeType.getValue(), name, "/docs/" + name,
                nodeType == NodeType.FILE ? "video/x-matroska" : null,
                1024L, false, null, Instant.now(), "PERSONAL", OWNER
        );
    }
}
