package com.omninest.modules.file.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.argThat;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.cache.ReadThroughCache;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.ratelimit.RateLimitService;
import com.omninest.common.security.CredentialCipher;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.modules.file.port.MediaCoverDirectory;
import com.omninest.modules.user.port.UserNameDirectory;
import com.omninest.common.storage.ObjectStorageKey;
import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncEventCommand;
import com.omninest.common.sync.UserSyncEventRecorder;
import com.omninest.common.user.UserAccountDetails;
import com.omninest.common.user.UserAccountQuery;
import com.omninest.modules.file.domain.FileFavorite;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.FileShareRecipient;
import com.omninest.modules.file.domain.FileObject;
import com.omninest.modules.file.domain.FileUploadSession;
import com.omninest.modules.file.domain.FileVersion;
import com.omninest.modules.file.domain.ShareLink;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.dto.AcceptShareRequest;
import com.omninest.modules.file.dto.AdminFileShareLinkDto;
import com.omninest.modules.file.dto.CreateShareLinkRequest;
import com.omninest.modules.file.dto.FileShareLinkDto;
import com.omninest.modules.file.dto.UpdateShareLinkRequest;
import com.omninest.modules.file.dto.FileSharePreviewDto;
import com.omninest.modules.file.repository.FileAccessRecordRepository;
import com.omninest.modules.file.repository.FileFavoriteRepository;
import com.omninest.modules.file.repository.FileNodeRepository;
import com.omninest.modules.file.repository.FileObjectRepository;
import com.omninest.modules.file.repository.FileVersionRepository;
import com.omninest.modules.file.repository.FileShareRecipientRepository;
import com.omninest.modules.file.repository.FileUploadSessionRepository;
import com.omninest.modules.file.repository.ShareLinkRepository;
import com.omninest.modules.file.repository.StorageExternalAccountRepository;
import com.omninest.modules.quota.service.StorageQuotaService;
import com.omninest.modules.notification.service.NotificationService;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.function.Supplier;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.ArgumentMatchers;
import org.mockito.Mockito;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.Pageable;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;

/**
 * 文件管理服务测试。
 *
 * @author OmniNest
 */
class FileManagerServiceTest {
    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID FILE_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");
    private static final UUID RECIPIENT_ID = UUID.fromString("30000000-0000-0000-0000-000000000001");
    private static final UUID SHARE_ID = UUID.fromString("40000000-0000-0000-0000-000000000001");
    private static final UUID OBJECT_ID = UUID.fromString("50000000-0000-0000-0000-000000000001");

    private final MediaCoverDirectory mediaCovers = (owner, ids) -> Map.of();
    private final UserNameDirectory userNamesById = userIds -> Map.of();
    private final FileNodeRepository fileNodeRepository = Mockito.mock(FileNodeRepository.class);
    private final FileAccessRecordRepository accessRecordRepository =
            Mockito.mock(FileAccessRecordRepository.class);
    private final FileFavoriteRepository favoriteRepository = Mockito.mock(FileFavoriteRepository.class);
    private final ShareLinkRepository shareLinkRepository = Mockito.mock(ShareLinkRepository.class);
    private final FileShareRecipientRepository shareRecipientRepository =
            Mockito.mock(FileShareRecipientRepository.class);
    private final FileUploadSessionRepository uploadSessionRepository =
            Mockito.mock(FileUploadSessionRepository.class);
    private final StorageExternalAccountRepository externalAccountRepository =
            Mockito.mock(StorageExternalAccountRepository.class);
    private final UserAccountQuery userAccountQuery = Mockito.mock(UserAccountQuery.class);
    private final FileObjectRepository fileObjectRepository = Mockito.mock(FileObjectRepository.class);
    private final FileVersionRepository fileVersionRepository = Mockito.mock(FileVersionRepository.class);
    private final FileContentChangePublisher fileContentChangePublisher = Mockito.mock(FileContentChangePublisher.class);
    private final ObjectStorageClient objectStorageClient = Mockito.mock(ObjectStorageClient.class);
    private final PasswordEncoder passwordEncoder = Mockito.mock(PasswordEncoder.class);
    /** 可逆替身：只验证令牌密文读写链路，不代表生产算法。 */
    private final CredentialCipher credentialCipher = new CredentialCipher() {
        @Override
        public String encrypt(String plaintext) {
            return "cipher:" + plaintext;
        }

        @Override
        public String decrypt(String payload) {
            return payload.startsWith("cipher:") ? payload.substring("cipher:".length()) : payload;
        }

        @Override
        public int currentKeyVersion() {
            return 1;
        }
    };
    private final FileQueryService fileQueryService = Mockito.mock(FileQueryService.class);
    private final RateLimitService rateLimitService =
            Mockito.mock(RateLimitService.class);
    private final ExternalStorageService externalStorageService = Mockito.mock(ExternalStorageService.class);
    private final NotificationService notificationService = Mockito.mock(NotificationService.class);
    private final FilePermissionService filePermissionService =
            Mockito.mock(FilePermissionService.class);
    private final UserSyncEventRecorder syncEventRecorder = Mockito.mock(UserSyncEventRecorder.class);
    private final StorageQuotaService storageQuotaService = Mockito.mock(StorageQuotaService.class);
    private final SharedSpaceQuotaService sharedSpaceQuotaService = Mockito.mock(SharedSpaceQuotaService.class);
    private final SharedSpaceService sharedSpaceService = Mockito.mock(SharedSpaceService.class);
    private final ResourceShareLinkService resourceShareLinkService =
            Mockito.mock(ResourceShareLinkService.class);
    private final ReadThroughCache readThroughCache = Mockito.mock(ReadThroughCache.class, invocation -> {
        if ("getOrLoad".equals(invocation.getMethod().getName())) {
            Supplier<?> loader = invocation.getArgument(2);
            return loader.get();
        }
        return null;
    });

    private final FileNodeSupport fileNodeSupport =
            new FileNodeSupport(userNamesById, mediaCovers, fileNodeRepository,
                    Mockito.mock(SharedSpaceService.class));
    private final FileSyncEventWriter syncEventWriter = new FileSyncEventWriter(syncEventRecorder);
    private final FileFavoriteService fileFavoriteService = new FileFavoriteService(
            favoriteRepository, fileNodeRepository, fileNodeSupport, syncEventWriter, sharedSpaceService);
    private final FileVersionService fileVersionService = new FileVersionService(
            fileNodeRepository, fileObjectRepository, fileVersionRepository, uploadSessionRepository,
            fileContentChangePublisher, fileNodeSupport, syncEventWriter,
            storageQuotaService, sharedSpaceQuotaService);
    private final FileShareService fileShareService = new FileShareService(
            fileNodeRepository, shareLinkRepository, shareRecipientRepository, passwordEncoder,
            filePermissionService, userAccountQuery, fileNodeSupport, syncEventWriter, readThroughCache,
            credentialCipher);
    private final FileShareAccessService fileShareAccessService = new FileShareAccessService(
            fileNodeRepository, shareLinkRepository, shareRecipientRepository, passwordEncoder, rateLimitService,
            notificationService, fileQueryService, resourceShareLinkService, readThroughCache, fileNodeSupport,
                storageQuotaService, syncEventRecorder, mock(FileIndexSyncService.class));
    private final FileUploadQueueService fileUploadQueueService = new FileUploadQueueService(uploadSessionRepository);
    private final ExternalStorageAccountService externalStorageAccountService = new ExternalStorageAccountService(
            externalAccountRepository, externalStorageService, mock(ExternalStorageCredentialService.class),
            mock(ExternalStorageOAuthService.class), mock(ExternalStorageEndpointGuard.class));
    private final FileManagerService fileManagerService = new FileManagerService(
            fileNodeRepository,
            accessRecordRepository,
            fileObjectRepository,
            objectStorageClient,
            fileNodeSupport,
            storageQuotaService,
            sharedSpaceQuotaService,
            sharedSpaceService,
            syncEventRecorder,
            mock(FileIndexSyncService.class)
    );

    @Test
    void listRecentFilesUsesAccessTimeDescending() {
        FileNode older = node("older.txt", "text/plain", 128);
        FileNode newer = node("newer.txt", "text/plain", 256);
        // 空间过滤在 SQL 侧完成，仓储只返回个人空间存活节点
        when(accessRecordRepository.findRecentNodes(
                eq(OWNER_ID), eq(SpaceType.PERSONAL), any(Pageable.class)))
                .thenReturn(List.of(newer, older));

        var result = fileManagerService.listRecentFiles(OWNER_ID);

        assertThat(result).extracting("name").containsExactly("newer.txt", "older.txt");
    }

    @Test
    void listFavoriteFilesOnlyReturnsCurrentUserFavorites() {
        FileNode file = node("starred.pdf", "application/pdf", 1024);
        file.setId(FILE_ID);
        when(favoriteRepository.findFavoriteNodeIds(eq(OWNER_ID), ArgumentMatchers.any(org.springframework.data.domain.Pageable.class)))
                .thenReturn(new org.springframework.data.domain.PageImpl<>(List.of(FILE_ID)));
        when(fileNodeRepository.findAllById(List.of(FILE_ID))).thenReturn(List.of(file));

        var result = fileFavoriteService.listFavoriteFilesPage(OWNER_ID, 0, 100);

        assertThat(result.getContent()).extracting("name").containsExactly("starred.pdf");
        verify(fileNodeRepository).findAllById(List.of(FILE_ID));
        verify(favoriteRepository, never()).findByOwnerUserIdOrderByCreatedAtDesc(OWNER_ID);
    }

    // ==================== 批量操作测试 ====================

    @Test
    void batchAddFavoritesIdempotentlySkipsExistingFavorites() {
        UUID file1Id = UUID.fromString("30000000-0000-0000-0000-000000000012");
        UUID file2Id = UUID.fromString("30000000-0000-0000-0000-000000000013");
        FileNode file1 = node("starred.pdf", "application/pdf", 1024);
        file1.setId(file1Id);
        FileNode file2 = node("new.pdf", "application/pdf", 2048);
        file2.setId(file2Id);
        when(fileNodeRepository.findAllById(List.of(file1Id, file2Id)))
                .thenReturn(List.of(file1, file2));
        when(favoriteRepository.findFavoritedNodeIds(OWNER_ID, List.of(file1Id, file2Id)))
                .thenReturn(List.of(file1Id));

        var result = fileFavoriteService.batchAddFavorites(OWNER_ID, List.of(file1Id, file2Id));

        @SuppressWarnings("unchecked")
        ArgumentCaptor<Iterable<FileFavorite>> captor =
                ArgumentCaptor.forClass(Iterable.class);
        verify(favoriteRepository).saveAll(captor.capture());
        List<FileFavorite> saved = new ArrayList<>();
        captor.getValue().forEach(saved::add);
        assertThat(saved).extracting(fav -> fav.getFileNode().getId()).containsExactly(file2Id);
        assertThat(result).hasSize(2);
    }

    @Test
    void batchAddFavoritesIncludesSharedNodesVisibleToUser() {
        UUID sharedId = UUID.fromString("30000000-0000-0000-0000-000000000016");
        FileNode shared = node("shared.pdf", "application/pdf", 4096);
        shared.setId(sharedId);
        shared.setOwnerUserId(UUID.fromString("99999999-9999-9999-9999-999999999999"));
        shared.setSpaceType(SpaceType.SHARED);
        when(fileNodeRepository.findAllById(List.of(sharedId))).thenReturn(List.of(shared));
        when(sharedSpaceService.canBrowse(OWNER_ID)).thenReturn(true);
        when(favoriteRepository.findFavoritedNodeIds(OWNER_ID, List.of(sharedId)))
                .thenReturn(List.of());

        var result = fileFavoriteService.batchAddFavorites(OWNER_ID, List.of(sharedId));

        assertThat(result).hasSize(1);
        verify(favoriteRepository).saveAll(any());
    }

    @Test
    void batchAddFavoritesSkipsSharedNodesWithoutBrowsePermission() {
        UUID sharedId = UUID.fromString("30000000-0000-0000-0000-000000000017");
        FileNode shared = node("shared.pdf", "application/pdf", 4096);
        shared.setId(sharedId);
        shared.setOwnerUserId(UUID.fromString("99999999-9999-9999-9999-999999999999"));
        shared.setSpaceType(SpaceType.SHARED);
        when(fileNodeRepository.findAllById(List.of(sharedId))).thenReturn(List.of(shared));
        when(sharedSpaceService.canBrowse(OWNER_ID)).thenReturn(false);

        var result = fileFavoriteService.batchAddFavorites(OWNER_ID, List.of(sharedId));

        assertThat(result).isEmpty();
        verify(favoriteRepository, never()).saveAll(any());
    }

    @Test
    void batchRemoveFavoritesDeletesByFileIds() {
        UUID file1Id = UUID.fromString("30000000-0000-0000-0000-000000000014");
        UUID file2Id = UUID.fromString("30000000-0000-0000-0000-000000000015");

        fileFavoriteService.batchRemoveFavorites(OWNER_ID, List.of(file1Id, file2Id));

        verify(favoriteRepository).deleteByOwnerUserIdAndFileNode_IdIn(
                OWNER_ID, List.of(file1Id, file2Id));
    }

    // ==================== 分享链接测试 ====================

    @Test
    void createShareWithRandomPasswordReturnsGeneratedPassword() {
        FileNode file = node("doc.pdf", "application/pdf", 1024);
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(FILE_ID, OWNER_ID))
                .thenReturn(Optional.of(file));
        when(shareLinkRepository.save(any(ShareLink.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));
        when(passwordEncoder.encode(any(String.class))).thenReturn("$2a$10$hashed");

        CreateShareLinkRequest request = new CreateShareLinkRequest(
                FILE_ID, "FILE", null, true, null, null, null);
        var result = fileShareService.createShare(OWNER_ID, request);

        assertThat(result.generatedPassword()).isNotNull();
        assertThat(result.generatedPassword()).hasSize(10);
        assertThat(result.generatedPassword()).matches("[a-zA-Z0-9]+");
        verify(passwordEncoder).encode(result.generatedPassword());
    }

    @Test
    void createShareDeduplicatesRecipientsAndRejectsSelfShare() {
        FileNode file = node("doc.pdf", "application/pdf", 1024);
        UUID recipient = UUID.fromString("40000000-0000-0000-0000-000000000001");
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(FILE_ID, OWNER_ID))
                .thenReturn(Optional.of(file));
        when(shareLinkRepository.save(any(ShareLink.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));
        when(userAccountQuery.findDetailsById(recipient))
                .thenReturn(Optional.of(activeAccount(recipient)));

        CreateShareLinkRequest duplicated = new CreateShareLinkRequest(
                FILE_ID, "FILE", null, false, null, null, List.of(recipient, recipient));
        fileShareService.createShare(OWNER_ID, duplicated);

        @SuppressWarnings("unchecked")
        ArgumentCaptor<Iterable<FileShareRecipient>> captor = ArgumentCaptor.forClass(Iterable.class);
        verify(shareRecipientRepository).saveAll(captor.capture());
        List<FileShareRecipient> saved = new ArrayList<>();
        captor.getValue().forEach(saved::add);
        assertThat(saved).hasSize(1);
        assertThat(saved.getFirst().getRecipientUserId()).isEqualTo(recipient);

        CreateShareLinkRequest self = new CreateShareLinkRequest(
                FILE_ID, "FILE", null, false, null, null, List.of(OWNER_ID));
        assertThatThrownBy(() -> fileShareService.createShare(OWNER_ID, self))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.PARAM_ERROR);
    }

    @Test
    void createShareRejectsMissingOrDisabledRecipient() {
        FileNode file = node("doc.pdf", "application/pdf", 1024);
        UUID missing = UUID.fromString("40000000-0000-0000-0000-000000000002");
        UUID disabled = UUID.fromString("40000000-0000-0000-0000-000000000003");
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(FILE_ID, OWNER_ID))
                .thenReturn(Optional.of(file));
        when(userAccountQuery.findDetailsById(missing)).thenReturn(Optional.empty());
        when(userAccountQuery.findDetailsById(disabled))
                .thenReturn(Optional.of(disabledAccount(disabled)));

        for (UUID recipient : List.of(missing, disabled)) {
            CreateShareLinkRequest request = new CreateShareLinkRequest(
                    FILE_ID, "FILE", null, false, null, null, List.of(recipient));
            assertThatThrownBy(() -> fileShareService.createShare(OWNER_ID, request))
                    .isInstanceOf(BusinessException.class)
                    .extracting(exception -> ((BusinessException) exception).errorCode())
                    .isEqualTo(ErrorCode.PARAM_ERROR);
        }
    }

    private UserAccountDetails activeAccount(UUID userId) {
        return new UserAccountDetails(userId, "recipient", "Recipient", null, null,
                "ACTIVE", null, Set.of(), Set.of(), 0L, 0L);
    }

    private UserAccountDetails disabledAccount(UUID userId) {
        return new UserAccountDetails(userId, "disabled", "Disabled", null, null,
                "DISABLED", null, Set.of(), Set.of(), 0L, 0L);
    }

    @Test
    void shareExpiresAtAcceptsIso8601AndLegacyWireFormat() {
        // ISO-8601 即时区（前端 toIso8601String / Swagger 契约形态）
        CreateShareLinkRequest iso = new CreateShareLinkRequest(
                FILE_ID, "FILE", null, false, "2026-09-26T00:00:00Z", null, null);
        assertThat(iso.parsedExpiresAt()).isEqualTo(Instant.parse("2026-09-26T00:00:00Z"));

        // Web 全局线格式 yyyy-MM-dd HH:mm:ss（按 UTC）
        CreateShareLinkRequest legacy = new CreateShareLinkRequest(
                FILE_ID, "FILE", null, false, "2026-09-26 00:00:00", null, null);
        assertThat(legacy.parsedExpiresAt()).isEqualTo(Instant.parse("2026-09-26T00:00:00Z"));

        // 空白与 null 容忍
        assertThat(new CreateShareLinkRequest(FILE_ID, "FILE", null, false, "  ", null, null)
                .parsedExpiresAt()).isNull();
        assertThat(new CreateShareLinkRequest(FILE_ID, "FILE", null, false, null, null, null)
                .parsedExpiresAt()).isNull();
    }

    @Test
    void createShareWithCustomPasswordDoesNotReturnGeneratedPassword() {
        FileNode file = node("doc.pdf", "application/pdf", 1024);
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(FILE_ID, OWNER_ID))
                .thenReturn(Optional.of(file));
        when(shareLinkRepository.save(any(ShareLink.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));
        when(passwordEncoder.encode("mypass")).thenReturn("$2a$10$hashed");

        CreateShareLinkRequest request = new CreateShareLinkRequest(
                FILE_ID, "FILE", "mypass", false, null, null, null);
        var result = fileShareService.createShare(OWNER_ID, request);

        assertThat(result.generatedPassword()).isNull();
        verify(passwordEncoder).encode("mypass");
    }

    @Test
    void previewShareReturnsFileInfoWithoutIncrementingAccessCount() {
        ShareLink link = shareLink("doc.pdf", null);
        when(rateLimitService.tryAcquire(any(), ArgumentMatchers.anyInt(), any(Duration.class))).thenReturn(true);
        when(shareLinkRepository.findByTokenHash(any())).thenReturn(Optional.of(link));
        FileNode file = node("doc.pdf", "application/pdf", 2048);
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(FILE_ID, OWNER_ID))
                .thenReturn(Optional.of(file));

        FileSharePreviewDto result = fileShareAccessService.previewShare("rawtoken", null);

        assertThat(result.fileName()).isEqualTo("doc.pdf");
        assertThat(result.sizeBytes()).isEqualTo(2048);
        assertThat(result.hasPassword()).isFalse();
        assertThat(link.getAccessCount()).isEqualTo(0);
    }

    @Test
    void previewShareRejectsWrongPassword() {
        ShareLink link = shareLink("doc.pdf", "$2a$10$hashed");
        when(rateLimitService.tryAcquire(any(), ArgumentMatchers.anyInt(), any(Duration.class))).thenReturn(true);
        when(shareLinkRepository.findByTokenHash(any())).thenReturn(Optional.of(link));
        when(passwordEncoder.matches("wrong", "$2a$10$hashed")).thenReturn(false);

        assertThatThrownBy(() -> fileShareAccessService.previewShare("rawtoken", "wrong"))
                .isInstanceOf(BusinessException.class)
                .hasFieldOrPropertyWithValue("errorCode", ErrorCode.PASSWORD_INVALID);
    }

    @Test
    void previewShareRejectsExpiredLink() {
        ShareLink link = shareLink("doc.pdf", null);
        link.setExpiresAt(Instant.parse("2020-01-01T00:00:00Z"));
        when(rateLimitService.tryAcquire(any(), ArgumentMatchers.anyInt(), any(Duration.class))).thenReturn(true);
        when(shareLinkRepository.findByTokenHash(any())).thenReturn(Optional.of(link));

        assertThatThrownBy(() -> fileShareAccessService.previewShare("rawtoken", null))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("过期");
    }

    @Test
    void previewShareRejectsRevokedLink() {
        ShareLink link = shareLink("doc.pdf", null);
        link.setDisabledAt(Instant.now());
        when(rateLimitService.tryAcquire(any(), ArgumentMatchers.anyInt(), any(Duration.class))).thenReturn(true);
        when(shareLinkRepository.findByTokenHash(any())).thenReturn(Optional.of(link));

        assertThatThrownBy(() -> fileShareAccessService.previewShare("rawtoken", null))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("撤销");
    }

    @Test
    void acceptShareCreatesFileNodeForRecipient() {
        ShareLink link = shareLink("doc.pdf", null);
        when(rateLimitService.tryAcquire(any(), ArgumentMatchers.anyInt(), any(Duration.class))).thenReturn(true);
        when(shareLinkRepository.findByTokenHash(any())).thenReturn(Optional.of(link));
        FileNode source = node("doc.pdf", "application/pdf", 2048);
        source.setCurrentObjectId(OBJECT_ID);
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(FILE_ID, OWNER_ID))
                .thenReturn(Optional.of(source));
        when(fileNodeRepository.findActiveByOwnerUserIdAndObjectId(RECIPIENT_ID, OBJECT_ID))
                .thenReturn(Optional.empty());
        when(fileNodeRepository.save(any(FileNode.class)))
                .thenAnswer(invocation -> {
                    FileNode saved = invocation.getArgument(0);
                    if (saved.getId() == null) {
                        saved.setId(UUID.randomUUID());
                    }
                    return saved;
                });
        when(shareLinkRepository.save(any(ShareLink.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        fileShareAccessService.acceptShare(RECIPIENT_ID, "rawtoken", new AcceptShareRequest(null, null));

        ArgumentCaptor<FileNode> captor = ArgumentCaptor.forClass(FileNode.class);
        verify(fileNodeRepository).save(captor.capture());
        FileNode saved = captor.getValue();
        assertThat(saved.getOwnerUserId()).isEqualTo(RECIPIENT_ID);
        assertThat(saved.getName()).isEqualTo("doc.pdf");
        assertThat(saved.getCurrentObjectId()).isEqualTo(OBJECT_ID);
        assertThat(saved.getSourceType()).isEqualTo("SHARE");
        assertThat(saved.getNodeType()).isEqualTo("FILE");
        assertThat(link.getAccessCount()).isEqualTo(1);
        // 转存进来的文件同样是接收方的占用：漏加计会让"转存—清空回收站"倒扣配额。
        verify(storageQuotaService).checkQuota(RECIPIENT_ID, 2048L);
        verify(storageQuotaService).incrementUsage(RECIPIENT_ID, 2048L);
    }

    @Test
    void acceptShareRejectsDuplicateFile() {
        ShareLink link = shareLink("doc.pdf", null);
        when(rateLimitService.tryAcquire(any(), ArgumentMatchers.anyInt(), any(Duration.class))).thenReturn(true);
        when(shareLinkRepository.findByTokenHash(any())).thenReturn(Optional.of(link));
        FileNode source = node("doc.pdf", "application/pdf", 2048);
        source.setCurrentObjectId(OBJECT_ID);
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(FILE_ID, OWNER_ID))
                .thenReturn(Optional.of(source));
        FileNode existing = node("doc.pdf", "application/pdf", 2048);
        when(fileNodeRepository.findActiveByOwnerUserIdAndObjectId(RECIPIENT_ID, OBJECT_ID))
                .thenReturn(Optional.of(existing));

        assertThatThrownBy(() -> fileShareAccessService.acceptShare(
                RECIPIENT_ID, "rawtoken", new AcceptShareRequest(null, null)))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("已存在");
    }

    @Test
    void acceptShareRejectsWrongPassword() {
        ShareLink link = shareLink("doc.pdf", "$2a$10$hashed");
        when(rateLimitService.tryAcquire(any(), ArgumentMatchers.anyInt(), any(Duration.class))).thenReturn(true);
        when(shareLinkRepository.findByTokenHash(any())).thenReturn(Optional.of(link));
        when(passwordEncoder.matches("wrong", "$2a$10$hashed")).thenReturn(false);

        assertThatThrownBy(() -> fileShareAccessService.acceptShare(
                RECIPIENT_ID, "rawtoken", new AcceptShareRequest("wrong", null)))
                .isInstanceOf(BusinessException.class)
                .hasFieldOrPropertyWithValue("errorCode", ErrorCode.PASSWORD_INVALID);
    }

    @Test
    void acceptShareRejectsDeletedSourceFile() {
        ShareLink link = shareLink("doc.pdf", null);
        when(rateLimitService.tryAcquire(any(), ArgumentMatchers.anyInt(), any(Duration.class))).thenReturn(true);
        when(shareLinkRepository.findByTokenHash(any())).thenReturn(Optional.of(link));
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(FILE_ID, OWNER_ID))
                .thenReturn(Optional.empty());

        assertThatThrownBy(() -> fileShareAccessService.acceptShare(
                RECIPIENT_ID, "rawtoken", new AcceptShareRequest(null, null)))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("不存在或已被删除");
    }

    @Test
    void acceptShareIncrementsAccessCount() {
        ShareLink link = shareLink("doc.pdf", null);
        link.setAccessCount(5);
        when(rateLimitService.tryAcquire(any(), ArgumentMatchers.anyInt(), any(Duration.class))).thenReturn(true);
        when(shareLinkRepository.findByTokenHash(any())).thenReturn(Optional.of(link));
        FileNode source = node("doc.pdf", "application/pdf", 1024);
        source.setCurrentObjectId(OBJECT_ID);
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(FILE_ID, OWNER_ID))
                .thenReturn(Optional.of(source));
        when(fileNodeRepository.findActiveByOwnerUserIdAndObjectId(RECIPIENT_ID, OBJECT_ID))
                .thenReturn(Optional.empty());
        when(fileNodeRepository.save(any(FileNode.class)))
                .thenAnswer(invocation -> {
                    FileNode saved = invocation.getArgument(0);
                    if (saved.getId() == null) {
                        saved.setId(UUID.randomUUID());
                    }
                    return saved;
                });
        when(shareLinkRepository.save(any(ShareLink.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        fileShareAccessService.acceptShare(RECIPIENT_ID, "rawtoken", new AcceptShareRequest(null, null));

        assertThat(link.getAccessCount()).isEqualTo(6);
    }

    @Test
    void acceptShareRejectsExhaustedAccessCount() {
        ShareLink link = shareLink("doc.pdf", null);
        link.setMaxAccessCount(10);
        link.setAccessCount(10);
        when(rateLimitService.tryAcquire(any(), ArgumentMatchers.anyInt(), any(Duration.class))).thenReturn(true);
        when(shareLinkRepository.findByTokenHash(any())).thenReturn(Optional.of(link));

        assertThatThrownBy(() -> fileShareAccessService.acceptShare(
                RECIPIENT_ID, "rawtoken", new AcceptShareRequest(null, null)))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("访问次数已达上限");
    }

    // ==================== 文件复制测试 ====================

    @Test
    void copyNode_createsNewNodeWithDifferentId() {
        UUID targetFolderId = UUID.fromString("60000000-0000-0000-0000-000000000001");
        FileNode source = node("report.pdf", "application/pdf", 2048);
        FileNode targetFolder = node("Documents", null, 0, "FOLDER");
        targetFolder.setId(targetFolderId);
        targetFolder.setNormalizedPath("/Documents");

        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(FILE_ID, OWNER_ID))
                .thenReturn(Optional.of(source));
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(targetFolderId, OWNER_ID))
                .thenReturn(Optional.of(targetFolder));
        when(fileNodeRepository.save(any(FileNode.class)))
                .thenAnswer(invocation -> {
                    FileNode saved = invocation.getArgument(0);
                    if (saved.getId() == null) {
                        saved.setId(UUID.randomUUID());
                    }
                    return saved;
                });

        var result = fileManagerService.copyNode(OWNER_ID, FILE_ID, targetFolderId);

        assertThat(result.id()).isNotEqualTo(FILE_ID);
        assertThat(result.name()).isEqualTo("report.pdf");
        assertThat(result.mimeType()).isEqualTo("application/pdf");
        assertThat(result.sizeBytes()).isEqualTo(2048);
        assertThat(result.parentId()).isEqualTo(targetFolderId);
        assertThat(result.normalizedPath()).isEqualTo("/Documents/report.pdf");
        // 副本必须按新节点加计配额：彻底删除副本时无条件扣减，不加计就能把已用空间刷空。
        verify(storageQuotaService).checkQuota(OWNER_ID, 2048L);
        verify(storageQuotaService).incrementUsage(OWNER_ID, 2048L);
        verify(syncEventRecorder).record(argThat(
                command -> command.action() == SyncAction.CREATED
                        && "FILE_NODE".equals(command.resourceType())));
    }

    @Test
    void restoreVersionRemovesPromotedVersionRowToAvoidDuplicates() {
        UUID versionId = UUID.fromString("70000000-0000-0000-0000-000000000001");
        UUID currentObjectId = UUID.fromString("70000000-0000-0000-0000-000000000002");
        UUID restoredObjectId = UUID.fromString("70000000-0000-0000-0000-000000000003");
        FileNode node = node("report.pdf", "application/pdf", 100);
        node.setCurrentObjectId(currentObjectId);
        FileVersion version = new FileVersion();
        version.setId(versionId);
        version.setFileNodeId(FILE_ID);
        version.setObjectId(restoredObjectId);
        version.setVersionNo(1);
        version.setChangeType("EDIT");
        FileObject restored = new FileObject();
        restored.setId(restoredObjectId);
        restored.setSizeBytes(200);
        restored.setMimeType("application/pdf");
        when(fileNodeRepository.findOwnedForUpdate(FILE_ID, OWNER_ID)).thenReturn(Optional.of(node));
        when(fileVersionRepository.findById(versionId)).thenReturn(Optional.of(version));
        when(fileVersionRepository.findMaxVersionNo(FILE_ID)).thenReturn(2);
        when(fileObjectRepository.findById(restoredObjectId)).thenReturn(Optional.of(restored));
        when(fileVersionRepository.save(any(FileVersion.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));
        when(fileNodeRepository.save(any(FileNode.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        fileVersionService.restoreVersion(OWNER_ID, FILE_ID, versionId);

        assertThat(node.getCurrentObjectId()).isEqualTo(restoredObjectId);
        verify(fileVersionRepository).delete(version);
        ArgumentCaptor<FileVersion> historyCaptor = ArgumentCaptor.forClass(FileVersion.class);
        verify(fileVersionRepository).save(historyCaptor.capture());
        assertThat(historyCaptor.getValue().getObjectId()).isEqualTo(currentObjectId);
        assertThat(historyCaptor.getValue().getChangeType()).isEqualTo("RESTORE");
    }

    @Test
    void copyNodeRejectsSharedSourceIntoPersonalRoot() {
        FileNode source = node("shared.pdf", "application/pdf", 2048);
        source.setSpaceType(SpaceType.SHARED);
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(FILE_ID, OWNER_ID))
                .thenReturn(Optional.of(source));

        assertThatThrownBy(() -> fileManagerService.copyNode(OWNER_ID, FILE_ID, null))
                .isInstanceOfSatisfying(BusinessException.class,
                        exception -> assertThat(exception.errorCode()).isEqualTo(ErrorCode.FORBIDDEN));
        verify(fileNodeRepository, Mockito.never()).save(any(FileNode.class));
    }

    @Test
    void copyNodeRequiresSharedWritePermissionForSharedTarget() {
        UUID targetFolderId = UUID.fromString("60000000-0000-0000-0000-000000000002");
        FileNode source = node("shared.pdf", "application/pdf", 2048);
        source.setSpaceType(SpaceType.SHARED);
        FileNode targetFolder = node("Shared", null, 0, "FOLDER");
        targetFolder.setId(targetFolderId);
        targetFolder.setSpaceType(SpaceType.SHARED);
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(FILE_ID, OWNER_ID))
                .thenReturn(Optional.of(source));
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(targetFolderId, OWNER_ID))
                .thenReturn(Optional.of(targetFolder));
        Mockito.doThrow(new BusinessException(ErrorCode.FORBIDDEN, "无权限执行此操作"))
                .when(sharedSpaceService).requireSharedWrite(OWNER_ID);

        assertThatThrownBy(() -> fileManagerService.copyNode(OWNER_ID, FILE_ID, targetFolderId))
                .isInstanceOfSatisfying(BusinessException.class,
                        exception -> assertThat(exception.errorCode()).isEqualTo(ErrorCode.FORBIDDEN));
        verify(fileNodeRepository, Mockito.never()).save(any(FileNode.class));
    }

    @Test
    void copyNodeChargesSharedQuotaWhenSharedWriteAllowed() {
        UUID targetFolderId = UUID.fromString("60000000-0000-0000-0000-000000000003");
        FileNode source = node("shared.pdf", "application/pdf", 2048);
        source.setSpaceType(SpaceType.SHARED);
        FileNode targetFolder = node("Shared", null, 0, "FOLDER");
        targetFolder.setId(targetFolderId);
        targetFolder.setSpaceType(SpaceType.SHARED);
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(FILE_ID, OWNER_ID))
                .thenReturn(Optional.of(source));
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(targetFolderId, OWNER_ID))
                .thenReturn(Optional.of(targetFolder));
        when(fileNodeRepository.existsBySpaceTypeAndParentIdAndNameAndDeletedFalse(
                SpaceType.SHARED, targetFolderId, "shared.pdf")).thenReturn(false);
        when(fileNodeRepository.save(any(FileNode.class))).thenAnswer(invocation -> {
            FileNode saved = invocation.getArgument(0);
            if (saved.getId() == null) {
                saved.setId(UUID.randomUUID());
            }
            return saved;
        });

        var result = fileManagerService.copyNode(OWNER_ID, FILE_ID, targetFolderId);

        assertThat(result.spaceType()).isEqualTo(SpaceType.SHARED.getValue());
        verify(sharedSpaceService).requireSharedWrite(OWNER_ID);
        verify(sharedSpaceQuotaService).checkQuota(2048L);
        verify(sharedSpaceQuotaService).increaseUsage(2048L, 1L);
        verify(storageQuotaService, Mockito.never()).incrementUsage(any(), anyLong());
    }

    @Test
    void copyNode_throwsWhenSourceNotFound() {
        UUID missingId = UUID.fromString("90000000-0000-0000-0000-000000000001");
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(missingId, OWNER_ID))
                .thenReturn(Optional.empty());

        assertThatThrownBy(() -> fileManagerService.copyNode(OWNER_ID, missingId, null))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("不存在");
    }

    @Test
    void copyNode_throwsWhenTargetParentNotFound() {
        UUID missingFolderId = UUID.fromString("90000000-0000-0000-0000-000000000002");
        FileNode source = node("photo.jpg", "image/jpeg", 1024);
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(FILE_ID, OWNER_ID))
                .thenReturn(Optional.of(source));
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(missingFolderId, OWNER_ID))
                .thenReturn(Optional.empty());

        assertThatThrownBy(() -> fileManagerService.copyNode(OWNER_ID, FILE_ID, missingFolderId))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("目标文件夹不存在");
    }

    @Test
    void copyNode_preservesCurrentObjectId() {
        FileNode source = node("report.pdf", "application/pdf", 2048);
        source.setCurrentObjectId(OBJECT_ID);
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(FILE_ID, OWNER_ID))
                .thenReturn(Optional.of(source));
        when(fileNodeRepository.existsByOwnerUserIdAndSpaceTypeAndParentIdIsNullAndNameAndDeletedFalse(
                OWNER_ID, SpaceType.PERSONAL, "report.pdf")).thenReturn(false);
        when(fileNodeRepository.save(any(FileNode.class)))
                .thenAnswer(invocation -> {
                    FileNode saved = invocation.getArgument(0);
                    if (saved.getId() == null) {
                        saved.setId(UUID.randomUUID());
                    }
                    return saved;
                });

        var result = fileManagerService.copyNode(OWNER_ID, FILE_ID, null);

        assertThat(result.name()).isEqualTo("report.pdf");
        verify(fileNodeRepository).save(any(FileNode.class));
    }

    @Test
    void copyNode_appendsSequenceWhenTargetAlreadyHasSameName() {
        FileNode source = node("report.pdf", "application/pdf", 2048);
        source.setCurrentObjectId(OBJECT_ID);
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(FILE_ID, OWNER_ID))
                .thenReturn(Optional.of(source));
        // 原名与 (1) 都被占用，副本必须落到 (2)，而不是把冲突抛给用户
        when(fileNodeRepository.existsByOwnerUserIdAndSpaceTypeAndParentIdIsNullAndNameAndDeletedFalse(
                OWNER_ID, SpaceType.PERSONAL, "report.pdf")).thenReturn(true);
        when(fileNodeRepository.existsByOwnerUserIdAndSpaceTypeAndParentIdIsNullAndNameAndDeletedFalse(
                OWNER_ID, SpaceType.PERSONAL, "report (1).pdf")).thenReturn(true);
        when(fileNodeRepository.existsByOwnerUserIdAndSpaceTypeAndParentIdIsNullAndNameAndDeletedFalse(
                OWNER_ID, SpaceType.PERSONAL, "report (2).pdf")).thenReturn(false);
        when(fileNodeRepository.save(any(FileNode.class)))
                .thenAnswer(invocation -> {
                    FileNode saved = invocation.getArgument(0);
                    if (saved.getId() == null) {
                        saved.setId(UUID.randomUUID());
                    }
                    return saved;
                });

        var result = fileManagerService.copyNode(OWNER_ID, FILE_ID, null);

        assertThat(result.name()).isEqualTo("report (2).pdf");
        assertThat(result.normalizedPath()).isEqualTo("/report (2).pdf");
        // 序号插在扩展名之前，副本仍按原扩展名识别
        verify(fileNodeRepository).save(argThat(copy -> "report (2).pdf".equals(copy.getName())
                && OBJECT_ID.equals(copy.getCurrentObjectId())));
    }

    @Test
    void copyNode_keepsFolderChildNamesWhenRootIsRenamed() {
        UUID folderId = UUID.fromString("90000000-0000-0000-0000-000000000005");
        FileNode folder = node("Album", null, 0, "FOLDER");
        folder.setId(folderId);
        folder.setNormalizedPath("/Album");
        FileNode child = node("inner.txt", "text/plain", 16);
        child.setId(UUID.fromString("90000000-0000-0000-0000-000000000006"));
        child.setParentId(folderId);
        child.setNormalizedPath("/Album/inner.txt");
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(folderId, OWNER_ID))
                .thenReturn(Optional.of(folder));
        when(fileNodeRepository.findByOwnerUserIdAndSpaceTypeAndNormalizedPathStartingWithAndDeletedFalse(
                OWNER_ID, SpaceType.PERSONAL, "/Album/")).thenReturn(List.of(child));
        when(fileNodeRepository.existsByOwnerUserIdAndSpaceTypeAndParentIdIsNullAndNameAndDeletedFalse(
                OWNER_ID, SpaceType.PERSONAL, "Album")).thenReturn(true);
        when(fileNodeRepository.save(any(FileNode.class)))
                .thenAnswer(invocation -> {
                    FileNode saved = invocation.getArgument(0);
                    if (saved.getId() == null) {
                        saved.setId(UUID.randomUUID());
                    }
                    return saved;
                });

        var result = fileManagerService.copyNode(OWNER_ID, folderId, null);

        // 只有顶层副本改名；子节点落在新建的父目录下，不可能与兄弟冲突
        assertThat(result.name()).isEqualTo("Album (1)");
        assertThat(result.normalizedPath()).isEqualTo("/Album (1)");
        verify(fileNodeRepository).save(argThat(copy -> "/Album (1)/inner.txt".equals(copy.getNormalizedPath())
                && "inner.txt".equals(copy.getName())));
    }

    @Test
    void copyNode_truncatesStemSoSuffixedNameFitsColumnWidth() {
        String longName = "x".repeat(250) + ".pdf";
        FileNode source = node(longName, "application/pdf", 2048);
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(FILE_ID, OWNER_ID))
                .thenReturn(Optional.of(source));
        when(fileNodeRepository.existsByOwnerUserIdAndSpaceTypeAndParentIdIsNullAndNameAndDeletedFalse(
                OWNER_ID, SpaceType.PERSONAL, longName)).thenReturn(true);
        when(fileNodeRepository.save(any(FileNode.class)))
                .thenAnswer(invocation -> {
                    FileNode saved = invocation.getArgument(0);
                    if (saved.getId() == null) {
                        saved.setId(UUID.randomUUID());
                    }
                    return saved;
                });

        var result = fileManagerService.copyNode(OWNER_ID, FILE_ID, null);

        assertThat(result.name()).hasSize(255);
        assertThat(result.name()).endsWith(" (1).pdf");
    }

    @Test
    void saveNewVersion_publishesContentChangeAndUpdatesMime() {
        FileNode node = node("report.pdf", "application/pdf", 100);
        node.setCurrentObjectId(OBJECT_ID);
        UUID newObjectId = UUID.fromString("50000000-0000-0000-0000-000000000002");
        FileObject newObject = new FileObject();
        newObject.setId(newObjectId);
        newObject.setObjectKey("uploads/" + OWNER_ID + "/session-1/report.pdf");
        newObject.setSizeBytes(200L);
        newObject.setMimeType("text/plain");

        when(fileNodeRepository.findOwnedForUpdate(FILE_ID, OWNER_ID))
                .thenReturn(Optional.of(node));
        when(fileObjectRepository.findById(newObjectId))
                .thenReturn(Optional.of(newObject));
        when(fileNodeRepository.findActiveByOwnerUserIdAndObjectId(OWNER_ID, newObjectId))
                .thenReturn(Optional.empty());
        when(uploadSessionRepository.findFirstByOwnerUserIdAndResultObjectId(OWNER_ID, newObjectId))
                .thenReturn(Optional.of(new FileUploadSession()));
        when(fileVersionRepository.findMaxVersionNo(FILE_ID)).thenReturn(0);
        when(fileNodeRepository.save(any(FileNode.class)))
                .thenAnswer(invocation -> {
                    FileNode saved = invocation.getArgument(0);
                    if (saved.getId() == null) {
                        saved.setId(UUID.randomUUID());
                    }
                    return saved;
                });

        var result = fileVersionService.saveNewVersion(OWNER_ID, FILE_ID, newObjectId, 200L, "replace");

        assertThat(result.sizeBytes()).isEqualTo(200L);
        assertThat(result.mimeType()).isEqualTo("text/plain");
        verify(fileContentChangePublisher).publish(any(FileNode.class), any(FileObject.class), any(UUID.class));
    }

    @Test
    void saveNewVersion_chargesQuotaOnDirectUploadPath() {
        FileNode node = node("report.pdf", "application/pdf", 100);
        node.setCurrentObjectId(OBJECT_ID);
        UUID newObjectId = UUID.fromString("50000000-0000-0000-0000-000000000020");
        FileObject newObject = new FileObject();
        newObject.setId(newObjectId);
        newObject.setObjectKey("uploads/" + OWNER_ID + "/session-2/report.pdf");
        newObject.setSizeBytes(200L);
        newObject.setMimeType("application/pdf");

        when(fileNodeRepository.findOwnedForUpdate(FILE_ID, OWNER_ID))
                .thenReturn(Optional.of(node));
        when(fileObjectRepository.findById(newObjectId))
                .thenReturn(Optional.of(newObject));
        when(fileNodeRepository.findActiveByOwnerUserIdAndObjectId(OWNER_ID, newObjectId))
                .thenReturn(Optional.empty());
        when(uploadSessionRepository.findFirstByOwnerUserIdAndResultObjectId(OWNER_ID, newObjectId))
                .thenReturn(Optional.of(new FileUploadSession()));
        when(fileVersionRepository.findMaxVersionNo(FILE_ID)).thenReturn(0);
        when(fileNodeRepository.save(any(FileNode.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        fileVersionService.saveNewVersion(OWNER_ID, FILE_ID, newObjectId, 200L, null, true);

        // 直接版本接口没有上传会话结算，必须由版本服务扣减新增对象字节。
        verify(storageQuotaService).checkQuota(OWNER_ID, 200L);
        verify(storageQuotaService).incrementUsage(OWNER_ID, 200L);
    }

    @Test
    void saveNewVersion_skipsQuotaWhenUploadSessionAlreadySettled() {
        FileNode node = node("report.pdf", "application/pdf", 100);
        node.setCurrentObjectId(OBJECT_ID);
        UUID newObjectId = UUID.fromString("50000000-0000-0000-0000-000000000021");
        FileObject newObject = new FileObject();
        newObject.setId(newObjectId);
        newObject.setObjectKey("users/" + OWNER_ID + "/files/report.pdf");
        newObject.setSizeBytes(200L);

        when(fileNodeRepository.findOwnedForUpdate(FILE_ID, OWNER_ID))
                .thenReturn(Optional.of(node));
        when(fileObjectRepository.findById(newObjectId))
                .thenReturn(Optional.of(newObject));
        when(fileNodeRepository.findActiveByOwnerUserIdAndObjectId(OWNER_ID, newObjectId))
                .thenReturn(Optional.empty());
        when(fileVersionRepository.findMaxVersionNo(FILE_ID)).thenReturn(0);
        when(fileNodeRepository.save(any(FileNode.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        fileVersionService.saveNewVersion(OWNER_ID, FILE_ID, newObjectId, 200L, null, false);

        // 入口晋升已由 settleUploadQuota 结算，版本服务不得重复加计。
        verify(storageQuotaService, never()).incrementUsage(any(), anyLong());
        verify(sharedSpaceQuotaService, never()).increaseUsage(anyLong(), anyLong());
    }

    @Test
    void saveNewVersion_rejectsLocalReadonlyNode() {
        FileNode node = node("movie.mkv", "video/x-matroska", 100);
        node.setCurrentObjectId(OBJECT_ID);
        node.setSourceType("LOCAL_FILESYSTEM");
        UUID newObjectId = UUID.fromString("50000000-0000-0000-0000-000000000010");
        FileObject newObject = new FileObject();
        newObject.setId(newObjectId);
        newObject.setObjectKey("users/" + OWNER_ID + "/movie.mkv");
        newObject.setSizeBytes(200L);

        when(fileNodeRepository.findOwnedForUpdate(FILE_ID, OWNER_ID))
                .thenReturn(Optional.of(node));
        when(fileObjectRepository.findById(newObjectId))
                .thenReturn(Optional.of(newObject));

        assertThatThrownBy(() ->
                fileVersionService.saveNewVersion(OWNER_ID, FILE_ID, newObjectId, 200L, null))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("本地只读");
        verify(fileVersionRepository, never()).save(any(FileVersion.class));
    }

    @Test
    void saveNewVersion_rejectsObjectOwnedByOtherUser() {
        FileNode node = node("report.pdf", "application/pdf", 100);
        node.setCurrentObjectId(OBJECT_ID);
        UUID foreignObjectId = UUID.fromString("50000000-0000-0000-0000-000000000099");
        FileObject foreignObject = new FileObject();
        foreignObject.setId(foreignObjectId);
        foreignObject.setObjectKey("uploads/other-user/session-1/a.pdf");
        foreignObject.setSizeBytes(100L);

        when(fileNodeRepository.findOwnedForUpdate(FILE_ID, OWNER_ID))
                .thenReturn(Optional.of(node));
        when(fileObjectRepository.findById(foreignObjectId))
                .thenReturn(Optional.of(foreignObject));

        assertThatThrownBy(() ->
                fileVersionService.saveNewVersion(OWNER_ID, FILE_ID, foreignObjectId, 100L, null))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("不属于");
    }

    @Test
    void saveNewVersion_rejectsObjectAliasedToOtherNode() {
        FileNode node = node("report.pdf", "application/pdf", 100);
        node.setCurrentObjectId(OBJECT_ID);
        UUID objectId = UUID.fromString("50000000-0000-0000-0000-000000000003");
        FileObject object = new FileObject();
        object.setId(objectId);
        object.setObjectKey("uploads/" + OWNER_ID + "/session-2/a.pdf");
        object.setSizeBytes(100L);
        FileNode other = node("other.pdf", "application/pdf", 100);
        other.setId(UUID.fromString("70000000-0000-0000-0000-000000000009"));

        when(fileNodeRepository.findOwnedForUpdate(FILE_ID, OWNER_ID))
                .thenReturn(Optional.of(node));
        when(fileObjectRepository.findById(objectId))
                .thenReturn(Optional.of(object));
        when(fileNodeRepository.findActiveByOwnerUserIdAndObjectId(OWNER_ID, objectId))
                .thenReturn(Optional.of(other));

        assertThatThrownBy(() ->
                fileVersionService.saveNewVersion(OWNER_ID, FILE_ID, objectId, 100L, null))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("已被其他文件");
    }

    @Test
    void saveNewVersion_rejectsObjectWithoutUploadSession() {
        FileNode node = node("report.pdf", "application/pdf", 100);
        node.setCurrentObjectId(OBJECT_ID);
        UUID objectId = UUID.fromString("50000000-0000-0000-0000-000000000004");
        FileObject object = new FileObject();
        object.setId(objectId);
        object.setObjectKey("uploads/" + OWNER_ID + "/session-3/a.pdf");
        object.setSizeBytes(100L);

        when(fileNodeRepository.findOwnedForUpdate(FILE_ID, OWNER_ID))
                .thenReturn(Optional.of(node));
        when(fileObjectRepository.findById(objectId))
                .thenReturn(Optional.of(object));
        when(fileNodeRepository.findActiveByOwnerUserIdAndObjectId(OWNER_ID, objectId))
                .thenReturn(Optional.empty());
        when(uploadSessionRepository.findFirstByOwnerUserIdAndResultObjectId(OWNER_ID, objectId))
                .thenReturn(Optional.empty());

        assertThatThrownBy(() ->
                fileVersionService.saveNewVersion(OWNER_ID, FILE_ID, objectId, 100L, null))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("上传会话");
    }

    @Test
    void copyNode_copiesToRootWhenTargetParentIsNull() {
        FileNode source = node("notes.txt", "text/plain", 512);
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(FILE_ID, OWNER_ID))
                .thenReturn(Optional.of(source));
        when(fileNodeRepository.save(any(FileNode.class)))
                .thenAnswer(invocation -> {
                    FileNode saved = invocation.getArgument(0);
                    if (saved.getId() == null) {
                        saved.setId(UUID.randomUUID());
                    }
                    return saved;
                });

        var result = fileManagerService.copyNode(OWNER_ID, FILE_ID, null);

        assertThat(result.id()).isNotEqualTo(FILE_ID);
        assertThat(result.name()).isEqualTo("notes.txt");
        assertThat(result.parentId()).isNull();
        assertThat(result.normalizedPath()).isEqualTo("/notes.txt");
    }

    // ==================== 批量打包下载测试 ====================

    /**
     * 打包路径改为一次批量读节点与对象后，桩必须覆盖 findAllById 而不是逐条 findById。
     */
    private static <T> List<T> keepKnown(Iterable<?> ids, Map<UUID, T> byId) {
        List<T> found = new ArrayList<>();
        for (Object rawId : ids) {
            T value = byId.get((UUID) rawId);
            if (value != null) {
                found.add(value);
            }
        }
        return found;
    }

    @Test
    void packAsZip_containsAllRequestedFiles() throws IOException {
        UUID file1Id = UUID.fromString("70000000-0000-0000-0000-000000000001");
        UUID file2Id = UUID.fromString("70000000-0000-0000-0000-000000000002");
        UUID file3Id = UUID.fromString("70000000-0000-0000-0000-000000000003");
        UUID obj1Id = UUID.fromString("80000000-0000-0000-0000-000000000001");
        UUID obj2Id = UUID.fromString("80000000-0000-0000-0000-000000000002");
        UUID obj3Id = UUID.fromString("80000000-0000-0000-0000-000000000003");

        FileNode file1 = node("doc.pdf", "application/pdf", 1024);
        file1.setId(file1Id);
        file1.setCurrentObjectId(obj1Id);
        FileNode file2 = node("photo.jpg", "image/jpeg", 2048);
        file2.setId(file2Id);
        file2.setCurrentObjectId(obj2Id);
        FileNode file3 = node("notes.txt", "text/plain", 512);
        file3.setId(file3Id);
        file3.setCurrentObjectId(obj3Id);

        FileObject obj1 = new FileObject();
        obj1.setId(obj1Id);
        obj1.setBucketName("files");
        obj1.setObjectKey("obj1");
        FileObject obj2 = new FileObject();
        obj2.setId(obj2Id);
        obj2.setBucketName("files");
        obj2.setObjectKey("obj2");
        FileObject obj3 = new FileObject();
        obj3.setId(obj3Id);
        obj3.setBucketName("files");
        obj3.setObjectKey("obj3");

        Map<UUID, FileNode> nodesById = Map.of(file1Id, file1, file2Id, file2, file3Id, file3);
        Map<UUID, FileObject> objectsById = Map.of(obj1Id, obj1, obj2Id, obj2, obj3Id, obj3);
        when(fileNodeRepository.findAllById(any())).thenAnswer(inv -> keepKnown(inv.getArgument(0), nodesById));
        when(fileObjectRepository.findAllById(any())).thenAnswer(inv -> keepKnown(inv.getArgument(0), objectsById));

        when(objectStorageClient.getObject(new ObjectStorageKey("files", "obj1")))
                .thenReturn(new ByteArrayInputStream("content1".getBytes()));
        when(objectStorageClient.getObject(new ObjectStorageKey("files", "obj2")))
                .thenReturn(new ByteArrayInputStream("content2".getBytes()));
        when(objectStorageClient.getObject(new ObjectStorageKey("files", "obj3")))
                .thenReturn(new ByteArrayInputStream("content3".getBytes()));

        ByteArrayOutputStream out = new ByteArrayOutputStream();
        fileManagerService.packAsZip(OWNER_ID,
                List.of(file1Id.toString(), file2Id.toString(), file3Id.toString()), out);

        // 验证 ZIP 包含 3 个条目
        try (ZipInputStream zis = new ZipInputStream(new ByteArrayInputStream(out.toByteArray()))) {
            ZipEntry entry;
            int count = 0;
            while ((entry = zis.getNextEntry()) != null) {
                count++;
                zis.closeEntry();
            }
            assertThat(count).isEqualTo(3);
        }
    }

    @Test
    void planZipEntriesDeduplicatesRepeatedFileIds() {
        UUID fileId = UUID.fromString("70000000-0000-0000-0000-000000000031");
        UUID objectId = UUID.fromString("80000000-0000-0000-0000-000000000031");
        FileNode file = node("same.pdf", "application/pdf", 1024);
        file.setId(fileId);
        file.setCurrentObjectId(objectId);
        FileObject object = new FileObject();
        object.setId(objectId);
        object.setBucketName("files");
        object.setObjectKey("obj31");
        object.setSizeBytes(1024);
        when(fileNodeRepository.findAllById(any())).thenReturn(List.of(file));
        when(fileObjectRepository.findAllById(any())).thenReturn(List.of(object));

        var entries = fileManagerService.planZipEntries(
                OWNER_ID, List.of(fileId.toString(), fileId.toString()));

        assertThat(entries).hasSize(1);
    }

    @Test
    void planZipEntriesRejectsPackagesAboveTotalByteLimit() {
        UUID fileId = UUID.fromString("70000000-0000-0000-0000-000000000032");
        UUID objectId = UUID.fromString("80000000-0000-0000-0000-000000000032");
        FileNode file = node("large.mkv", "video/x-matroska", 2048);
        file.setId(fileId);
        file.setCurrentObjectId(objectId);
        FileObject object = new FileObject();
        object.setId(objectId);
        object.setBucketName("files");
        object.setObjectKey("obj32");
        object.setSizeBytes(2048);
        when(fileNodeRepository.findAllById(any())).thenReturn(List.of(file));
        when(fileObjectRepository.findAllById(any())).thenReturn(List.of(object));
        fileManagerService.setMaxBatchDownloadTotalBytes(1024);

        assertThatThrownBy(() -> fileManagerService.planZipEntries(OWNER_ID, List.of(fileId.toString())))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("打包总大小超过限制");
    }

    @Test
    void batchDownloadLeaseCapsConcurrentPackages() {
        var first = fileManagerService.acquireBatchDownloadLease();
        var second = fileManagerService.acquireBatchDownloadLease();
        assertThatThrownBy(fileManagerService::acquireBatchDownloadLease)
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("批量下载任务过多");
        first.close();
        var third = fileManagerService.acquireBatchDownloadLease();
        second.close();
        third.close();
    }

    @Test
    void packAsZip_skipsFolders() throws IOException {
        UUID folderId = UUID.fromString("70000000-0000-0000-0000-000000000010");
        UUID fileId = UUID.fromString("70000000-0000-0000-0000-000000000011");
        UUID objId = UUID.fromString("80000000-0000-0000-0000-000000000011");

        FileNode folder = node("Documents", null, 0, "FOLDER");
        folder.setId(folderId);
        FileNode file = node("report.pdf", "application/pdf", 2048);
        file.setId(fileId);
        file.setCurrentObjectId(objId);

        Map<UUID, FileNode> packNodes = Map.of(folderId, folder, fileId, file);
        FileObject obj = new FileObject();
        obj.setId(objId);
        obj.setBucketName("files");
        obj.setObjectKey("obj11");
        Map<UUID, FileObject> packObjects = Map.of(objId, obj);
        when(fileNodeRepository.findAllById(any())).thenAnswer(inv -> keepKnown(inv.getArgument(0), packNodes));
        when(fileObjectRepository.findAllById(any())).thenAnswer(inv -> keepKnown(inv.getArgument(0), packObjects));
        when(objectStorageClient.getObject(new ObjectStorageKey("files", "obj11")))
                .thenReturn(new ByteArrayInputStream("report-content".getBytes()));

        ByteArrayOutputStream out = new ByteArrayOutputStream();
        fileManagerService.packAsZip(OWNER_ID,
                List.of(folderId.toString(), fileId.toString()), out);

        // 验证 ZIP 仅包含 1 个条目（跳过了文件夹）
        try (ZipInputStream zis = new ZipInputStream(new ByteArrayInputStream(out.toByteArray()))) {
            ZipEntry entry;
            int count = 0;
            while ((entry = zis.getNextEntry()) != null) {
                count++;
                assertThat(entry.getName()).isEqualTo("report.pdf");
                zis.closeEntry();
            }
            assertThat(count).isEqualTo(1);
        }
    }

    @Test
    void packAsZip_deduplicatesSameNameAndSkipsTrashedNode() throws IOException {
        UUID firstId = UUID.fromString("70000000-0000-0000-0000-000000000021");
        UUID secondId = UUID.fromString("70000000-0000-0000-0000-000000000022");
        UUID trashedId = UUID.fromString("70000000-0000-0000-0000-000000000023");
        UUID obj1 = UUID.fromString("80000000-0000-0000-0000-000000000021");
        UUID obj2 = UUID.fromString("80000000-0000-0000-0000-000000000022");
        UUID obj3 = UUID.fromString("80000000-0000-0000-0000-000000000023");

        FileNode reportA = node("report.pdf", "application/pdf", 1024);
        reportA.setId(firstId);
        reportA.setCurrentObjectId(obj1);
        FileNode reportB = node("report.pdf", "application/pdf", 2048);
        reportB.setId(secondId);
        reportB.setCurrentObjectId(obj2);
        FileNode trashed = node("gone.txt", "text/plain", 512);
        trashed.setId(trashedId);
        trashed.setCurrentObjectId(obj3);
        trashed.setDeleted(true);

        Map<UUID, FileNode> dedupeNodes = Map.of(firstId, reportA, secondId, reportB, trashedId, trashed);
        Map<UUID, FileObject> dedupeObjects = new HashMap<>();
        for (UUID objectId : List.of(obj1, obj2, obj3)) {
            FileObject object = new FileObject();
            object.setId(objectId);
            object.setBucketName("files");
            object.setObjectKey("obj-" + objectId);
            dedupeObjects.put(objectId, object);
            when(objectStorageClient.getObject(new ObjectStorageKey("files", "obj-" + objectId)))
                    .thenReturn(new ByteArrayInputStream("payload".getBytes()));
        }
        when(fileNodeRepository.findAllById(any())).thenAnswer(inv -> keepKnown(inv.getArgument(0), dedupeNodes));
        when(fileObjectRepository.findAllById(any())).thenAnswer(inv -> keepKnown(inv.getArgument(0), dedupeObjects));

        ByteArrayOutputStream out = new ByteArrayOutputStream();
        fileManagerService.packAsZip(
                OWNER_ID, List.of(firstId.toString(), secondId.toString(), trashedId.toString()), out);

        List<String> entryNames = new ArrayList<>();
        try (ZipInputStream zis = new ZipInputStream(new ByteArrayInputStream(out.toByteArray()))) {
            ZipEntry entry;
            while ((entry = zis.getNextEntry()) != null) {
                entryNames.add(entry.getName());
                zis.closeEntry();
            }
        }
        // 首个同名条目保持原名，第二个追加序号；回收站节点不入包
        assertThat(entryNames).containsExactly("report.pdf", "report (1).pdf");
    }

    // ==================== 端到端分享流程测试 ====================

    @Test
    void shareFlowCreatePreviewAcceptWithRandomPassword() {
        // 使用真实的 BCrypt 编码器验证完整密码流程
        BCryptPasswordEncoder realEncoder =
                new BCryptPasswordEncoder();
        FileShareService realShareService = new FileShareService(
                fileNodeRepository, shareLinkRepository, shareRecipientRepository, realEncoder,
                filePermissionService, userAccountQuery, fileNodeSupport, syncEventWriter, readThroughCache,
                credentialCipher);
        FileShareAccessService realAccessService = new FileShareAccessService(
                fileNodeRepository, shareLinkRepository, shareRecipientRepository, realEncoder, rateLimitService,
                notificationService, fileQueryService, resourceShareLinkService, readThroughCache, fileNodeSupport,
                storageQuotaService, syncEventRecorder, mock(FileIndexSyncService.class));

        // 模拟：文件存在
        FileNode file = node("report.xlsx", "application/vnd.ms-excel", 4096);
        file.setCurrentObjectId(OBJECT_ID);
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(FILE_ID, OWNER_ID))
                .thenReturn(Optional.of(file));
        when(fileNodeRepository.findByIdAndOwnerUserId(FILE_ID, OWNER_ID))
                .thenReturn(Optional.of(file));
        when(shareLinkRepository.save(any(ShareLink.class)))
                .thenAnswer(invocation -> {
                    ShareLink link = invocation.getArgument(0);
                    if (link.getId() == null) link.setId(SHARE_ID);
                    return link;
                });
        when(rateLimitService.tryAcquire(any(), ArgumentMatchers.anyInt(), any(Duration.class)))
                .thenReturn(true);

        // 步骤1：创建带随机密码的分享
        CreateShareLinkRequest createRequest = new CreateShareLinkRequest(
                FILE_ID, "FILE", null, true, null, null, null);
        var createResult = realShareService.createShare(OWNER_ID, createRequest);

        assertThat(createResult.generatedPassword()).isNotNull();
        assertThat(createResult.generatedPassword()).hasSize(10);
        String plainPassword = createResult.generatedPassword();

        // 提取存储的密码哈希（从 save 调用中捕获）
        ArgumentCaptor<ShareLink> linkCaptor = ArgumentCaptor.forClass(ShareLink.class);
        verify(shareLinkRepository, Mockito.atLeastOnce()).save(linkCaptor.capture());
        ShareLink savedLink = linkCaptor.getValue();
        String storedHash = savedLink.getPasswordHash();
        assertThat(storedHash).isNotNull();
        assertThat(realEncoder.matches(plainPassword, storedHash)).isTrue();

        // 步骤2：用正确密码预览 → 成功
        ShareLink previewLink = new ShareLink();
        previewLink.setId(SHARE_ID);
        previewLink.setOwnerUserId(OWNER_ID);
        previewLink.setResourceType("FILE");
        previewLink.setResourceId(FILE_ID);
        previewLink.setTokenHash("deadbeef");
        previewLink.setPasswordHash(storedHash);
        previewLink.setAccessCount(0);
        stubAccessConsumption(previewLink);
        when(shareLinkRepository.findByTokenHash(any())).thenReturn(Optional.of(previewLink));

        FileSharePreviewDto preview = realAccessService.previewShare("rawtoken", plainPassword);
        assertThat(preview.fileName()).isEqualTo("report.xlsx");
        assertThat(preview.hasPassword()).isTrue();
        assertThat(previewLink.getAccessCount()).isEqualTo(0); // 预览不计数

        // 步骤3：用错误密码预览 → 失败
        assertThatThrownBy(() -> realAccessService.previewShare("rawtoken", "wrongpassword"))
                .isInstanceOf(BusinessException.class)
                .hasFieldOrPropertyWithValue("errorCode", ErrorCode.PASSWORD_INVALID);

        // 步骤4：用正确密码接受 → 成功
        when(fileNodeRepository.findActiveByOwnerUserIdAndObjectId(RECIPIENT_ID, OBJECT_ID))
                .thenReturn(Optional.empty());
        when(fileNodeRepository.save(any(FileNode.class)))
                .thenAnswer(invocation -> {
                    FileNode saved = invocation.getArgument(0);
                    if (saved.getId() == null) {
                        saved.setId(UUID.randomUUID());
                    }
                    return saved;
                });

        realAccessService.acceptShare(RECIPIENT_ID, "rawtoken", new AcceptShareRequest(plainPassword, null));

        ArgumentCaptor<FileNode> nodeCaptor = ArgumentCaptor.forClass(FileNode.class);
        verify(fileNodeRepository).save(nodeCaptor.capture());
        FileNode savedNode = nodeCaptor.getValue();
        assertThat(savedNode.getOwnerUserId()).isEqualTo(RECIPIENT_ID);
        assertThat(savedNode.getName()).isEqualTo("report.xlsx");
        assertThat(savedNode.getCurrentObjectId()).isEqualTo(OBJECT_ID);
        assertThat(savedNode.getSourceType()).isEqualTo("SHARE");
        assertThat(previewLink.getAccessCount()).isEqualTo(1); // 接受时计数

        // 步骤5：用错误密码接受 → 失败
        assertThatThrownBy(() -> realAccessService.acceptShare(
                RECIPIENT_ID, "rawtoken", new AcceptShareRequest("wrongpassword", null)))
                .isInstanceOf(BusinessException.class)
                .hasFieldOrPropertyWithValue("errorCode", ErrorCode.PASSWORD_INVALID);
    }

    @Test
    void shareFlowCreatePreviewAcceptWithCustomPassword() {
        BCryptPasswordEncoder realEncoder =
                new BCryptPasswordEncoder();
        FileShareService realShareService = new FileShareService(
                fileNodeRepository, shareLinkRepository, shareRecipientRepository, realEncoder,
                filePermissionService, userAccountQuery, fileNodeSupport, syncEventWriter, readThroughCache,
                credentialCipher);
        FileShareAccessService realAccessService = new FileShareAccessService(
                fileNodeRepository, shareLinkRepository, shareRecipientRepository, realEncoder, rateLimitService,
                notificationService, fileQueryService, resourceShareLinkService, readThroughCache, fileNodeSupport,
                storageQuotaService, syncEventRecorder, mock(FileIndexSyncService.class));

        FileNode file = node("photo.jpg", "image/jpeg", 2048);
        file.setCurrentObjectId(OBJECT_ID);
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(FILE_ID, OWNER_ID))
                .thenReturn(Optional.of(file));
        when(fileNodeRepository.findByIdAndOwnerUserId(FILE_ID, OWNER_ID))
                .thenReturn(Optional.of(file));
        when(shareLinkRepository.save(any(ShareLink.class)))
                .thenAnswer(invocation -> {
                    ShareLink link = invocation.getArgument(0);
                    if (link.getId() == null) link.setId(SHARE_ID);
                    return link;
                });
        when(rateLimitService.tryAcquire(any(), ArgumentMatchers.anyInt(), any(Duration.class)))
                .thenReturn(true);

        // 创建带自定义密码的分享
        CreateShareLinkRequest createRequest = new CreateShareLinkRequest(
                FILE_ID, "FILE", "MySecret123", false, null, null, null);
        var createResult = realShareService.createShare(OWNER_ID, createRequest);

        // 自定义密码不应返回 generatedPassword
        assertThat(createResult.generatedPassword()).isNull();

        // 提取存储的哈希
        ArgumentCaptor<ShareLink> linkCaptor = ArgumentCaptor.forClass(ShareLink.class);
        verify(shareLinkRepository, Mockito.atLeastOnce()).save(linkCaptor.capture());
        String storedHash = linkCaptor.getValue().getPasswordHash();
        assertThat(realEncoder.matches("MySecret123", storedHash)).isTrue();

        // 用正确密码预览
        ShareLink previewLink = new ShareLink();
        previewLink.setId(SHARE_ID);
        previewLink.setOwnerUserId(OWNER_ID);
        previewLink.setResourceType("FILE");
        previewLink.setResourceId(FILE_ID);
        previewLink.setTokenHash("deadbeef");
        previewLink.setPasswordHash(storedHash);
        previewLink.setAccessCount(0);
        stubAccessConsumption(previewLink);
        when(shareLinkRepository.findByTokenHash(any())).thenReturn(Optional.of(previewLink));

        FileSharePreviewDto preview = realAccessService.previewShare("rawtoken", "MySecret123");
        assertThat(preview.fileName()).isEqualTo("photo.jpg");

        // 用错误密码预览
        assertThatThrownBy(() -> realAccessService.previewShare("rawtoken", "wrong"))
                .isInstanceOf(BusinessException.class)
                .hasFieldOrPropertyWithValue("errorCode", ErrorCode.PASSWORD_INVALID);
    }

    // ==================== 分享令牌回显测试 ====================

    /**
     * 「我的分享」列表回显的分享码必须能兑换公开访问：创建时落库的密文可解回明文，
     * 且该明文的哈希就是访问路径比对的 token_hash。回退到哈希片段会让复制链接 404。
     */
    @Test
    void listMySharesRevealsRedeemableToken() {
        FileNode file = node("share-target.pdf", "application/pdf", 1024);
        file.setCurrentObjectId(OBJECT_ID);
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(FILE_ID, OWNER_ID))
                .thenReturn(Optional.of(file));
        when(fileNodeRepository.findByIdAndOwnerUserId(FILE_ID, OWNER_ID))
                .thenReturn(Optional.of(file));
        when(shareLinkRepository.save(any(ShareLink.class))).thenAnswer(invocation -> {
            ShareLink link = invocation.getArgument(0);
            if (link.getId() == null) {
                link.setId(SHARE_ID);
            }
            return link;
        });

        String createdCode = fileShareService.createShare(
                OWNER_ID,
                new CreateShareLinkRequest(FILE_ID, "FILE", null, false, null, null, null)).shareCode();

        ArgumentCaptor<ShareLink> savedLink = ArgumentCaptor.forClass(ShareLink.class);
        verify(shareLinkRepository).save(savedLink.capture());
        ShareLink stored = savedLink.getValue();
        assertThat(stored.getTokenCipher()).isNotBlank();
        // 替身是"前缀 + 原文"的可逆实现，所以只能断言不是裸令牌；真实密文由 CredentialCipher 保证。
        assertThat(stored.getTokenCipher()).isNotEqualTo(createdCode);

        when(shareLinkRepository.findActiveByOwnerPage(eq(OWNER_ID), any(Pageable.class)))
                .thenReturn(new PageImpl<>(List.of(stored)));
        FileShareLinkDto listed = fileShareService.listMySharesPage(OWNER_ID, 0, 20).getContent().get(0);

        assertThat(listed.shareCode()).isEqualTo(createdCode);
        assertThat(FileShareService.sha256(listed.shareCode())).isEqualTo(stored.getTokenHash());
    }

    /** 历史行没有密文时不得伪造地址：回显空串，调用方据此判定"无地址"。 */
    @Test
    void listMySharesWithoutCipherYieldsEmptyCode() {
        ShareLink legacy = new ShareLink();
        legacy.setId(SHARE_ID);
        legacy.setOwnerUserId(OWNER_ID);
        legacy.setResourceType("FILE");
        legacy.setResourceId(FILE_ID);
        legacy.setTokenHash("0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef");
        legacy.setAccessCount(0);
        when(shareLinkRepository.findActiveByOwnerPage(eq(OWNER_ID), any(Pageable.class)))
                .thenReturn(new PageImpl<>(List.of(legacy)));

        FileShareLinkDto listed = fileShareService.listMySharesPage(OWNER_ID, 0, 20).getContent().get(0);

        assertThat(listed.shareCode()).isEmpty();
    }

    /** 修改分享设置不得换令牌：已经发出去的地址必须继续可用。 */
    @Test
    void updateShareKeepsTokenAndAppliesNewSettings() {
        ShareLink stored = existingShare(0);
        when(shareLinkRepository.findByIdAndOwnerUserId(SHARE_ID, OWNER_ID)).thenReturn(Optional.of(stored));
        when(shareLinkRepository.save(any(ShareLink.class))).thenAnswer(invocation -> invocation.getArgument(0));
        String tokenHashBefore = stored.getTokenHash();
        String tokenCipherBefore = stored.getTokenCipher();

        FileShareLinkDto updated = fileShareService.updateShare(
                OWNER_ID,
                SHARE_ID,
                new UpdateShareLinkRequest(null, "2099-01-01T00:00:00Z", 5));

        assertThat(stored.getTokenHash()).isEqualTo(tokenHashBefore);
        assertThat(stored.getTokenCipher()).isEqualTo(tokenCipherBefore);
        assertThat(stored.getMaxAccessCount()).isEqualTo(5);
        assertThat(stored.getExpiresAt()).isNotNull();
        // 不传密码即保持原值，不能被当成"清除密码"。
        assertThat(stored.getPasswordHash()).isNull();
        assertThat(updated.shareCode()).isEqualTo("plain-token-1");
        verify(readThroughCache).invalidate("omninest:share:link:" + tokenHashBefore);
    }

    /** 空白密码是"清除密码"，0 是"不限次数"，两者都必须能显式表达。 */
    @Test
    void updateShareBlankPasswordAndZeroLimitClearSettings() {
        ShareLink stored = existingShare(3);
        stored.setPasswordHash("hashed-old");
        stored.setMaxAccessCount(20);
        when(shareLinkRepository.findByIdAndOwnerUserId(SHARE_ID, OWNER_ID)).thenReturn(Optional.of(stored));
        when(shareLinkRepository.save(any(ShareLink.class))).thenAnswer(invocation -> invocation.getArgument(0));

        fileShareService.updateShare(OWNER_ID, SHARE_ID, new UpdateShareLinkRequest("", "", 0));

        assertThat(stored.getPasswordHash()).isNull();
        assertThat(stored.getExpiresAt()).isNull();
        assertThat(stored.getMaxAccessCount()).isNull();
    }

    /** 上限低于已访问次数会把分享直接判成耗尽，必须拒绝而不是静默生效。 */
    @Test
    void updateShareRejectsLimitBelowAccessCount() {
        ShareLink stored = existingShare(10);
        when(shareLinkRepository.findByIdAndOwnerUserId(SHARE_ID, OWNER_ID)).thenReturn(Optional.of(stored));

        assertThatThrownBy(() -> fileShareService.updateShare(
                OWNER_ID, SHARE_ID, new UpdateShareLinkRequest(null, null, 5)))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("已访问次数");

        verify(shareLinkRepository, never()).save(any(ShareLink.class));
    }

    /** 已撤销的分享不能再改设置，否则撤销语义会变成"可恢复"。 */
    @Test
    void updateShareRejectsRevokedLink() {
        ShareLink stored = existingShare(0);
        stored.setDisabledAt(Instant.parse("2026-01-01T00:00:00Z"));
        when(shareLinkRepository.findByIdAndOwnerUserId(SHARE_ID, OWNER_ID)).thenReturn(Optional.of(stored));

        assertThatThrownBy(() -> fileShareService.updateShare(
                OWNER_ID, SHARE_ID, new UpdateShareLinkRequest(null, "2099-01-01T00:00:00Z", null)))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("已撤销");
    }

    /** 全站列表要带所有者身份与已删资源占位名，管理员据此定位是谁发的链接。 */
    @Test
    void listAllSharesPageIncludesOwnerAndDeletedResourcePlaceholder() {
        ShareLink stored = existingShare(2);
        when(shareLinkRepository.findAllActivePage(any(Pageable.class)))
                .thenReturn(new PageImpl<>(List.of(stored)));
        when(userAccountQuery.findUsernames(List.of(OWNER_ID))).thenReturn(Map.of(OWNER_ID, "alice"));
        when(fileNodeRepository.findAllById(List.of(FILE_ID))).thenReturn(List.of());

        AdminFileShareLinkDto listed =
                fileShareService.listAllSharesPage(OWNER_ID, 0, 50).getContent().get(0);

        assertThat(listed.ownerUserId()).isEqualTo(OWNER_ID);
        assertThat(listed.ownerUsername()).isEqualTo("alice");
        assertThat(listed.resourceName()).isEqualTo("已删除文件");
        assertThat(listed.status()).isEqualTo("ACTIVE");
    }

    @Test
    void listAllSharesPageMasksOtherUsersPersonalResourceName() {
        UUID otherOwner = UUID.fromString("10000000-0000-0000-0000-000000000077");
        UUID operator = UUID.fromString("10000000-0000-0000-0000-000000000099");
        ShareLink stored = existingShare(0);
        stored.setOwnerUserId(otherOwner);
        when(shareLinkRepository.findAllActivePage(any(Pageable.class)))
                .thenReturn(new PageImpl<>(List.of(stored)));
        when(userAccountQuery.findUsernames(List.of(otherOwner))).thenReturn(Map.of(otherOwner, "bob"));
        FileNode node = new FileNode();
        node.setId(FILE_ID);
        node.setOwnerUserId(otherOwner);
        node.setName("私密体检报告.pdf");
        node.setSpaceType(SpaceType.PERSONAL);
        when(fileNodeRepository.findAllById(List.of(FILE_ID))).thenReturn(List.of(node));

        AdminFileShareLinkDto listed =
                fileShareService.listAllSharesPage(operator, 0, 50).getContent().get(0);

        assertThat(listed.resourceName()).isEqualTo("私人文件");
    }

    @Test
    void listAllSharesPageKeepsSharedSpaceResourceName() {
        UUID otherOwner = UUID.fromString("10000000-0000-0000-0000-000000000078");
        UUID operator = UUID.fromString("10000000-0000-0000-0000-000000000099");
        ShareLink stored = existingShare(0);
        stored.setOwnerUserId(otherOwner);
        when(shareLinkRepository.findAllActivePage(any(Pageable.class)))
                .thenReturn(new PageImpl<>(List.of(stored)));
        when(userAccountQuery.findUsernames(List.of(otherOwner))).thenReturn(Map.of(otherOwner, "bob"));
        FileNode node = new FileNode();
        node.setId(FILE_ID);
        node.setOwnerUserId(otherOwner);
        node.setName("团队公告.pdf");
        node.setSpaceType(SpaceType.SHARED);
        when(fileNodeRepository.findAllById(List.of(FILE_ID))).thenReturn(List.of(node));

        AdminFileShareLinkDto listed =
                fileShareService.listAllSharesPage(operator, 0, 50).getContent().get(0);

        assertThat(listed.resourceName()).isEqualTo("团队公告.pdf");
    }

    private ShareLink existingShare(int accessCount) {
        ShareLink link = new ShareLink();
        link.setId(SHARE_ID);
        link.setOwnerUserId(OWNER_ID);
        link.setResourceType("FILE");
        link.setResourceId(FILE_ID);
        link.setTokenHash("0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef");
        // credentialCipher 替身是 "cipher:" + 原文，因此密文去掉前缀即明文令牌。
        link.setTokenCipher("cipher:plain-token-1");
        link.setAccessCount(accessCount);
        link.setCreatedAt(Instant.parse("2026-01-01T00:00:00Z"));
        return link;
    }

    private FileFavorite favorite(FileNode node) {
        FileFavorite favorite = new FileFavorite();
        favorite.setOwnerUserId(OWNER_ID);
        favorite.setFileNode(node);
        favorite.setCreatedAt(Instant.parse("2026-05-20T08:00:00Z"));
        return favorite;
    }

    private ShareLink shareLink(String resourceName, String passwordHash) {
        ShareLink link = new ShareLink();
        link.setId(SHARE_ID);
        link.setOwnerUserId(OWNER_ID);
        link.setResourceType("FILE");
        link.setResourceId(FILE_ID);
        link.setTokenHash("deadbeef");
        link.setPasswordHash(passwordHash);
        link.setAccessCount(0);
        stubAccessConsumption(link);
        return link;
    }

    private void stubAccessConsumption(ShareLink link) {
        when(shareLinkRepository.consumeAccess(Mockito.eq(link.getId()), any(Instant.class)))
                .thenAnswer(invocation -> {
                    if (link.getMaxAccessCount() != null
                            && link.getAccessCount() >= link.getMaxAccessCount()) {
                        return 0;
                    }
                    link.setAccessCount(link.getAccessCount() + 1);
                    return 1;
                });
        when(shareLinkRepository.findById(link.getId())).thenReturn(Optional.of(link));
    }

    private FileNode node(String name, String mimeType, long sizeBytes) {
        return node(name, mimeType, sizeBytes, "FILE");
    }

    private FileNode node(String name, String mimeType, long sizeBytes, String nodeType) {
        FileNode node = new FileNode();
        node.setId(FILE_ID);
        node.setOwnerUserId(OWNER_ID);
        node.setName(name);
        node.setNodeType(nodeType);
        node.setNormalizedPath("/" + name);
        node.setMimeType(mimeType);
        node.setSizeBytes(sizeBytes);
        return node;
    }
}
