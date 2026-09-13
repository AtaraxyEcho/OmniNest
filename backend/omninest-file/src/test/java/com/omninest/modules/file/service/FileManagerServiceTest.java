package com.omninest.modules.file.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.argThat;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.cache.ReadThroughCache;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.ratelimit.RateLimitService;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.common.storage.ObjectStorageKey;
import com.omninest.common.sync.UserSyncEventRecorder;
import com.omninest.common.user.UserAccountQuery;
import com.omninest.modules.file.domain.FileAccessRecord;
import com.omninest.modules.file.domain.FileFavorite;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.FileObject;
import com.omninest.modules.file.domain.ShareLink;
import com.omninest.modules.file.dto.AcceptShareRequest;
import com.omninest.modules.file.dto.CreateShareLinkRequest;
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
import com.omninest.modules.notification.service.NotificationService;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import java.util.function.Supplier;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.ArgumentMatchers;
import org.mockito.Mockito;
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
    private final FileQueryService fileQueryService = Mockito.mock(FileQueryService.class);
    private final RateLimitService rateLimitService =
            Mockito.mock(RateLimitService.class);
    private final ExternalStorageService externalStorageService = Mockito.mock(ExternalStorageService.class);
    private final NotificationService notificationService = Mockito.mock(NotificationService.class);
    private final FilePermissionService filePermissionService =
            Mockito.mock(FilePermissionService.class);
    private final UserSyncEventRecorder syncEventRecorder = Mockito.mock(UserSyncEventRecorder.class);
    private final ResourceShareLinkService resourceShareLinkService =
            Mockito.mock(ResourceShareLinkService.class);
    private final ReadThroughCache readThroughCache = Mockito.mock(ReadThroughCache.class, invocation -> {
        if ("getOrLoad".equals(invocation.getMethod().getName())) {
            Supplier<?> loader = invocation.getArgument(2);
            return loader.get();
        }
        return null;
    });

    private final FileManagerService fileManagerService = new FileManagerService(
            fileNodeRepository,
            accessRecordRepository,
            favoriteRepository,
            shareLinkRepository,
            shareRecipientRepository,
            uploadSessionRepository,
            externalAccountRepository,
            userAccountQuery,
            fileObjectRepository,
            fileVersionRepository,
            fileContentChangePublisher,
            objectStorageClient,
            passwordEncoder,
            fileQueryService,
            filePermissionService,
            rateLimitService,
            notificationService,
            externalStorageService,
            readThroughCache,
            syncEventRecorder,
            resourceShareLinkService
    );

    @Test
    void listRecentFilesUsesAccessTimeDescending() {
        FileNode older = node("older.txt", "text/plain", 128);
        FileNode newer = node("newer.txt", "text/plain", 256);
        FileAccessRecord olderRecord = accessRecord(older, "2026-05-19T08:00:00Z");
        FileAccessRecord newerRecord = accessRecord(newer, "2026-05-20T08:00:00Z");
        when(accessRecordRepository.findTop50ByOwnerUserIdOrderByLastAccessedAtDesc(OWNER_ID))
                .thenReturn(List.of(newerRecord, olderRecord));

        var result = fileManagerService.listRecentFiles(OWNER_ID);

        assertThat(result).extracting("name").containsExactly("newer.txt", "older.txt");
    }

    @Test
    void listFavoriteFilesOnlyReturnsCurrentUserFavorites() {
        FileNode file = node("starred.pdf", "application/pdf", 1024);
        when(favoriteRepository.findByOwnerUserIdOrderByCreatedAtDesc(OWNER_ID))
                .thenReturn(List.of(favorite(file)));

        var result = fileManagerService.listFavoriteFiles(OWNER_ID);

        assertThat(result).extracting("name").containsExactly("starred.pdf");
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
        when(fileNodeRepository.findByOwnerUserIdAndIdInAndDeletedFalse(
                OWNER_ID, List.of(file1Id, file2Id)))
                .thenReturn(List.of(file1, file2));
        when(favoriteRepository.existsByOwnerUserIdAndFileNode_Id(OWNER_ID, file1Id))
                .thenReturn(true);
        when(favoriteRepository.existsByOwnerUserIdAndFileNode_Id(OWNER_ID, file2Id))
                .thenReturn(false);

        var result = fileManagerService.batchAddFavorites(OWNER_ID, List.of(file1Id, file2Id));

        verify(favoriteRepository, never()).save(argThat(fav ->
                ((FileFavorite) fav).getFileNode().getId().equals(file1Id)));
        verify(favoriteRepository).save(argThat(fav ->
                ((FileFavorite) fav).getFileNode().getId().equals(file2Id)));
        assertThat(result).hasSize(2);
    }

    @Test
    void batchRemoveFavoritesDeletesByFileIds() {
        UUID file1Id = UUID.fromString("30000000-0000-0000-0000-000000000014");
        UUID file2Id = UUID.fromString("30000000-0000-0000-0000-000000000015");

        fileManagerService.batchRemoveFavorites(OWNER_ID, List.of(file1Id, file2Id));

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
        var result = fileManagerService.createShare(OWNER_ID, request);

        assertThat(result.generatedPassword()).isNotNull();
        assertThat(result.generatedPassword()).hasSize(6);
        assertThat(result.generatedPassword()).matches("[a-zA-Z0-9]+");
        verify(passwordEncoder).encode(result.generatedPassword());
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
        var result = fileManagerService.createShare(OWNER_ID, request);

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

        FileSharePreviewDto result = fileManagerService.previewShare("rawtoken", null);

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

        assertThatThrownBy(() -> fileManagerService.previewShare("rawtoken", "wrong"))
                .isInstanceOf(BusinessException.class)
                .hasFieldOrPropertyWithValue("errorCode", ErrorCode.UNAUTHORIZED);
    }

    @Test
    void previewShareRejectsExpiredLink() {
        ShareLink link = shareLink("doc.pdf", null);
        link.setExpiresAt(Instant.parse("2020-01-01T00:00:00Z"));
        when(rateLimitService.tryAcquire(any(), ArgumentMatchers.anyInt(), any(Duration.class))).thenReturn(true);
        when(shareLinkRepository.findByTokenHash(any())).thenReturn(Optional.of(link));

        assertThatThrownBy(() -> fileManagerService.previewShare("rawtoken", null))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("过期");
    }

    @Test
    void previewShareRejectsRevokedLink() {
        ShareLink link = shareLink("doc.pdf", null);
        link.setDisabledAt(Instant.now());
        when(rateLimitService.tryAcquire(any(), ArgumentMatchers.anyInt(), any(Duration.class))).thenReturn(true);
        when(shareLinkRepository.findByTokenHash(any())).thenReturn(Optional.of(link));

        assertThatThrownBy(() -> fileManagerService.previewShare("rawtoken", null))
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
                .thenAnswer(invocation -> invocation.getArgument(0));
        when(shareLinkRepository.save(any(ShareLink.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        fileManagerService.acceptShare(RECIPIENT_ID, "rawtoken", new AcceptShareRequest(null, null));

        ArgumentCaptor<FileNode> captor = ArgumentCaptor.forClass(FileNode.class);
        verify(fileNodeRepository).save(captor.capture());
        FileNode saved = captor.getValue();
        assertThat(saved.getOwnerUserId()).isEqualTo(RECIPIENT_ID);
        assertThat(saved.getName()).isEqualTo("doc.pdf");
        assertThat(saved.getCurrentObjectId()).isEqualTo(OBJECT_ID);
        assertThat(saved.getSourceType()).isEqualTo("SHARE");
        assertThat(saved.getNodeType()).isEqualTo("FILE");
        assertThat(link.getAccessCount()).isEqualTo(1);
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

        assertThatThrownBy(() -> fileManagerService.acceptShare(
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

        assertThatThrownBy(() -> fileManagerService.acceptShare(
                RECIPIENT_ID, "rawtoken", new AcceptShareRequest("wrong", null)))
                .isInstanceOf(BusinessException.class)
                .hasFieldOrPropertyWithValue("errorCode", ErrorCode.UNAUTHORIZED);
    }

    @Test
    void acceptShareRejectsDeletedSourceFile() {
        ShareLink link = shareLink("doc.pdf", null);
        when(rateLimitService.tryAcquire(any(), ArgumentMatchers.anyInt(), any(Duration.class))).thenReturn(true);
        when(shareLinkRepository.findByTokenHash(any())).thenReturn(Optional.of(link));
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(FILE_ID, OWNER_ID))
                .thenReturn(Optional.empty());

        assertThatThrownBy(() -> fileManagerService.acceptShare(
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
                .thenAnswer(invocation -> invocation.getArgument(0));
        when(shareLinkRepository.save(any(ShareLink.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        fileManagerService.acceptShare(RECIPIENT_ID, "rawtoken", new AcceptShareRequest(null, null));

        assertThat(link.getAccessCount()).isEqualTo(6);
    }

    @Test
    void acceptShareRejectsExhaustedAccessCount() {
        ShareLink link = shareLink("doc.pdf", null);
        link.setMaxAccessCount(10);
        link.setAccessCount(10);
        when(rateLimitService.tryAcquire(any(), ArgumentMatchers.anyInt(), any(Duration.class))).thenReturn(true);
        when(shareLinkRepository.findByTokenHash(any())).thenReturn(Optional.of(link));

        assertThatThrownBy(() -> fileManagerService.acceptShare(
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
        when(fileNodeRepository.existsByOwnerUserIdAndParentIdIsNullAndNameAndDeletedFalse(
                OWNER_ID, "report.pdf")).thenReturn(false);
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
    void copyNode_rejectsSameNameInTargetParent() {
        FileNode source = node("report.pdf", "application/pdf", 2048);
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(FILE_ID, OWNER_ID))
                .thenReturn(Optional.of(source));
        when(fileNodeRepository.existsByOwnerUserIdAndParentIdIsNullAndNameAndDeletedFalse(
                OWNER_ID, "report.pdf")).thenReturn(true);

        assertThatThrownBy(() -> fileManagerService.copyNode(OWNER_ID, FILE_ID, null))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("同名");
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
                .thenReturn(Optional.of(new com.omninest.modules.file.domain.FileUploadSession()));
        when(fileVersionRepository.findMaxVersionNo(FILE_ID)).thenReturn(0);
        when(fileNodeRepository.save(any(FileNode.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        var result = fileManagerService.saveNewVersion(OWNER_ID, FILE_ID, newObjectId, 200L, "replace");

        assertThat(result.sizeBytes()).isEqualTo(200L);
        assertThat(result.mimeType()).isEqualTo("text/plain");
        verify(fileContentChangePublisher).publish(any(FileNode.class), any(FileObject.class), any(UUID.class));
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
                fileManagerService.saveNewVersion(OWNER_ID, FILE_ID, foreignObjectId, 100L, null))
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
                fileManagerService.saveNewVersion(OWNER_ID, FILE_ID, objectId, 100L, null))
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
                fileManagerService.saveNewVersion(OWNER_ID, FILE_ID, objectId, 100L, null))
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

        when(fileNodeRepository.findByIdAndOwnerUserId(file1Id, OWNER_ID))
                .thenReturn(Optional.of(file1));
        when(fileNodeRepository.findByIdAndOwnerUserId(file2Id, OWNER_ID))
                .thenReturn(Optional.of(file2));
        when(fileNodeRepository.findByIdAndOwnerUserId(file3Id, OWNER_ID))
                .thenReturn(Optional.of(file3));

        FileObject obj1 = new FileObject();
        obj1.setBucketName("files");
        obj1.setObjectKey("obj1");
        FileObject obj2 = new FileObject();
        obj2.setBucketName("files");
        obj2.setObjectKey("obj2");
        FileObject obj3 = new FileObject();
        obj3.setBucketName("files");
        obj3.setObjectKey("obj3");

        when(fileObjectRepository.findById(obj1Id)).thenReturn(Optional.of(obj1));
        when(fileObjectRepository.findById(obj2Id)).thenReturn(Optional.of(obj2));
        when(fileObjectRepository.findById(obj3Id)).thenReturn(Optional.of(obj3));

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
    void packAsZip_skipsFolders() throws IOException {
        UUID folderId = UUID.fromString("70000000-0000-0000-0000-000000000010");
        UUID fileId = UUID.fromString("70000000-0000-0000-0000-000000000011");
        UUID objId = UUID.fromString("80000000-0000-0000-0000-000000000011");

        FileNode folder = node("Documents", null, 0, "FOLDER");
        folder.setId(folderId);
        FileNode file = node("report.pdf", "application/pdf", 2048);
        file.setId(fileId);
        file.setCurrentObjectId(objId);

        when(fileNodeRepository.findByIdAndOwnerUserId(folderId, OWNER_ID))
                .thenReturn(Optional.of(folder));
        when(fileNodeRepository.findByIdAndOwnerUserId(fileId, OWNER_ID))
                .thenReturn(Optional.of(file));

        FileObject obj = new FileObject();
        obj.setBucketName("files");
        obj.setObjectKey("obj11");
        when(fileObjectRepository.findById(objId)).thenReturn(Optional.of(obj));
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

    // ==================== 端到端分享流程测试 ====================

    @Test
    void shareFlowCreatePreviewAcceptWithRandomPassword() {
        // 使用真实的 BCrypt 编码器验证完整密码流程
        BCryptPasswordEncoder realEncoder =
                new BCryptPasswordEncoder();
        FileManagerService realService = new FileManagerService(
                fileNodeRepository, accessRecordRepository, favoriteRepository,
                shareLinkRepository, shareRecipientRepository, uploadSessionRepository,
                externalAccountRepository, userAccountQuery, fileObjectRepository, fileVersionRepository,
                fileContentChangePublisher,
                objectStorageClient,
                realEncoder, fileQueryService, filePermissionService,
                rateLimitService, notificationService,
                externalStorageService, readThroughCache, syncEventRecorder,
                resourceShareLinkService
        );

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
        var createResult = realService.createShare(OWNER_ID, createRequest);

        assertThat(createResult.generatedPassword()).isNotNull();
        assertThat(createResult.generatedPassword()).hasSize(6);
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

        FileSharePreviewDto preview = realService.previewShare("rawtoken", plainPassword);
        assertThat(preview.fileName()).isEqualTo("report.xlsx");
        assertThat(preview.hasPassword()).isTrue();
        assertThat(previewLink.getAccessCount()).isEqualTo(0); // 预览不计数

        // 步骤3：用错误密码预览 → 失败
        assertThatThrownBy(() -> realService.previewShare("rawtoken", "wrongpassword"))
                .isInstanceOf(BusinessException.class)
                .hasFieldOrPropertyWithValue("errorCode", ErrorCode.UNAUTHORIZED);

        // 步骤4：用正确密码接受 → 成功
        when(fileNodeRepository.findActiveByOwnerUserIdAndObjectId(RECIPIENT_ID, OBJECT_ID))
                .thenReturn(Optional.empty());
        when(fileNodeRepository.save(any(FileNode.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        realService.acceptShare(RECIPIENT_ID, "rawtoken", new AcceptShareRequest(plainPassword, null));

        ArgumentCaptor<FileNode> nodeCaptor = ArgumentCaptor.forClass(FileNode.class);
        verify(fileNodeRepository).save(nodeCaptor.capture());
        FileNode savedNode = nodeCaptor.getValue();
        assertThat(savedNode.getOwnerUserId()).isEqualTo(RECIPIENT_ID);
        assertThat(savedNode.getName()).isEqualTo("report.xlsx");
        assertThat(savedNode.getCurrentObjectId()).isEqualTo(OBJECT_ID);
        assertThat(savedNode.getSourceType()).isEqualTo("SHARE");
        assertThat(previewLink.getAccessCount()).isEqualTo(1); // 接受时计数

        // 步骤5：用错误密码接受 → 失败
        assertThatThrownBy(() -> realService.acceptShare(
                RECIPIENT_ID, "rawtoken", new AcceptShareRequest("wrongpassword", null)))
                .isInstanceOf(BusinessException.class)
                .hasFieldOrPropertyWithValue("errorCode", ErrorCode.UNAUTHORIZED);
    }

    @Test
    void shareFlowCreatePreviewAcceptWithCustomPassword() {
        BCryptPasswordEncoder realEncoder =
                new BCryptPasswordEncoder();
        FileManagerService realService = new FileManagerService(
                fileNodeRepository, accessRecordRepository, favoriteRepository,
                shareLinkRepository, shareRecipientRepository, uploadSessionRepository,
                externalAccountRepository, userAccountQuery, fileObjectRepository, fileVersionRepository,
                fileContentChangePublisher,
                objectStorageClient,
                realEncoder, fileQueryService, filePermissionService,
                rateLimitService, notificationService,
                externalStorageService, readThroughCache, syncEventRecorder,
                resourceShareLinkService
        );

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
        var createResult = realService.createShare(OWNER_ID, createRequest);

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

        FileSharePreviewDto preview = realService.previewShare("rawtoken", "MySecret123");
        assertThat(preview.fileName()).isEqualTo("photo.jpg");

        // 用错误密码预览
        assertThatThrownBy(() -> realService.previewShare("rawtoken", "wrong"))
                .isInstanceOf(BusinessException.class)
                .hasFieldOrPropertyWithValue("errorCode", ErrorCode.UNAUTHORIZED);
    }

    private FileAccessRecord accessRecord(FileNode node, String lastAccessedAt) {
        FileAccessRecord record = new FileAccessRecord();
        record.setOwnerUserId(OWNER_ID);
        record.setFileNode(node);
        record.setLastAccessedAt(Instant.parse(lastAccessedAt));
        return record;
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
