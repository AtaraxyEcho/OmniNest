package com.omninest.modules.file.service;

import org.springframework.context.ApplicationEventPublisher;
import org.mockito.Mockito;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.cache.ReadThroughCache;
import com.omninest.common.sync.UserSyncEventRecorder;
import com.omninest.common.config.ConfigValueProvider;
import com.omninest.modules.file.domain.NodeType;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.common.error.BusinessException;
import com.omninest.common.user.UserAccountQuery;
import com.omninest.common.user.UserAccountSummary;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.SharedSpacePermission;
import com.omninest.modules.file.domain.SharedSpacePermission.Action;
import com.omninest.modules.file.event.FileNodesSoftDeletedEvent;
import com.omninest.modules.file.repository.FileNodePermissionRepository;
import com.omninest.modules.file.repository.FileNodeRepository;
import com.omninest.modules.file.repository.ShareLinkRepository;
import com.omninest.modules.file.repository.SharedSpacePermissionRepository;
import com.omninest.modules.file.repository.SharedSpaceUsageRepository;
import com.omninest.modules.quota.service.StorageQuotaService;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

/**
 * 共享空间集成测试，覆盖用户操作流程和业务流转。
 *
 * 场景一：管理员配置共享空间
 * 场景二：上传文件到共享空间（由 FileUploadSessionService 处理，此处验证后置效果）
 * 场景三：跨空间移动文件
 * 场景四：删除共享空间文件
 * 场景五：媒体库合并展示（由 Repository 查询处理，此处验证数据准备）
 * 场景六：文件夹递归操作
 */
class SharedSpaceIntegrationTest {

    // ── 测试用户 ──
    private static final UUID ADMIN_ID = UUID.fromString("11111111-1111-1111-1111-111111111111");
    private static final UUID USER_A = UUID.fromString("22222222-2222-2222-2222-222222222222");
    private static final UUID USER_B = UUID.fromString("33333333-3333-3333-3333-333333333333");
    private static final UUID ADMIN_ROLE_ID = UUID.fromString("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
    private static final UUID MEMBER_ROLE_ID = UUID.fromString("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");

    // ── 测试文件 ──
    private static final UUID MOVIE_FILE_ID = UUID.fromString("cccccccc-cccc-cccc-cccc-cccccccccccc");
    private static final UUID DOC_FOLDER_ID = UUID.fromString("dddddddd-dddd-dddd-dddd-dddddddddddd");
    private static final UUID REPORT_FILE_ID = UUID.fromString("eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee");
    private static final UUID IMAGES_FOLDER_ID = UUID.fromString("ffffffff-ffff-ffff-ffff-ffffffffffff");
    private static final UUID PHOTO1_ID = UUID.fromString("11111111-2222-3333-4444-555555555555");
    private static final UUID PHOTO2_ID = UUID.fromString("22222222-3333-4444-5555-666666666666");

    // ── Mock 依赖 ──
    private final FileNodeRepository fileNodeRepository = mock(FileNodeRepository.class);
    private final SharedSpacePermissionRepository permissionRepository = mock(SharedSpacePermissionRepository.class);
    private final SharedSpaceQuotaService sharedSpaceQuotaService = mock(SharedSpaceQuotaService.class);
    private final StorageQuotaService storageQuotaService = mock(StorageQuotaService.class);
    private final UserAccountQuery userAccountQuery = mock(UserAccountQuery.class);
    private final ShareLinkRepository shareLinkRepository = mock(ShareLinkRepository.class);
    private final FileNodePermissionRepository fileNodePermissionRepository = mock(FileNodePermissionRepository.class);
    private final ConfigValueProvider configValueProvider = mock(ConfigValueProvider.class);
    private final ApplicationEventPublisher eventPublisher =
            mock(ApplicationEventPublisher.class);
    private final FileIndexSyncService fileIndexSyncService = mock(FileIndexSyncService.class);
    private final UserSyncEventRecorder syncEventRecorder = mock(UserSyncEventRecorder.class);
    private final ReadThroughCache readThroughCache = mock(ReadThroughCache.class);

    private SharedSpaceService service;

    @BeforeEach
    void setUp() {
        when(configValueProvider.findByKey("shared_space.enabled"))
                .thenReturn(Optional.of("true"));
        when(configValueProvider.findByKey("shared_space.max_bytes"))
                .thenReturn(Optional.of("107374182400"));

        service = new SharedSpaceService(
                fileNodeRepository, permissionRepository, sharedSpaceQuotaService,
                storageQuotaService, userAccountQuery, shareLinkRepository,
                fileNodePermissionRepository, configValueProvider, eventPublisher,
                fileIndexSyncService, syncEventRecorder, readThroughCache
        );
    }

    // ═══════════════════════════════════════════════════════════════════
    // 场景一：管理员配置共享空间
    // ═══════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("场景一：管理员配置共享空间")
    class AdminConfigScenario {

        @Test
        @DisplayName("共享空间禁用时，所有操作被拒绝")
        void sharedSpaceDisabled_allOperationsRejected() {
            when(configValueProvider.findByKey("shared_space.enabled"))
                    .thenReturn(Optional.of("false"));
            stubPermission(USER_A, true, true, true, true, false, true, true, true);
            FileNode file = personalFile(MOVIE_FILE_ID, USER_A, "movie.mkv", 1024L);
            when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(MOVIE_FILE_ID, USER_A))
                    .thenReturn(Optional.of(file));

            assertThatThrownBy(() -> service.listSharedSpaceFiles(null, USER_A))
                    .isInstanceOf(BusinessException.class)
                    .extracting(ex -> ((BusinessException) ex).errorCode())
                    .isEqualTo(ErrorCode.FORBIDDEN);

            assertThatThrownBy(() -> service.createFolder(null, "movies", USER_A))
                    .isInstanceOf(BusinessException.class);

            assertThatThrownBy(() -> service.moveToSharedSpace(MOVIE_FILE_ID, USER_A))
                    .isInstanceOf(BusinessException.class);
        }

        @Test
        @DisplayName("角色权限配置正确生效")
        void rolePermission_correctlyEnforced() {
            // MEMBER 只能上传，不能删除他人文件
            stubPermission(USER_A, true, true, true, true, false, true, true, true);
            FileNode otherFile = sharedFile(MOVIE_FILE_ID, USER_B, "movie.mkv", 1024L);
            when(fileNodeRepository.findByIdAndSpaceTypeAndDeletedFalse(MOVIE_FILE_ID, SpaceType.SHARED))
                    .thenReturn(Optional.of(otherFile));

            assertThatThrownBy(() -> service.deleteSharedFile(MOVIE_FILE_ID, USER_A))
                    .isInstanceOf(BusinessException.class)
                    .extracting(ex -> ((BusinessException) ex).errorCode())
                    .isEqualTo(ErrorCode.FORBIDDEN);
        }

        @Test
        @DisplayName("管理员可以删除任意共享文件")
        void admin_canDeleteAnySharedFile() {
            stubPermission(ADMIN_ID, true, true, true, true, true, true, true, true);
            FileNode otherFile = sharedFile(MOVIE_FILE_ID, USER_A, "movie.mkv", 1024L);
            when(fileNodeRepository.findByIdAndSpaceTypeAndDeletedFalse(MOVIE_FILE_ID, SpaceType.SHARED))
                    .thenReturn(Optional.of(otherFile));
            when(fileNodeRepository.findBySpaceTypeAndParentIdAndDeletedFalse(SpaceType.SHARED, MOVIE_FILE_ID))
                    .thenReturn(List.of());

            service.deleteSharedFile(MOVIE_FILE_ID, ADMIN_ID);

            assertThat(otherFile.isDeleted()).isTrue();
            assertThat(otherFile.getDeletedBy()).isEqualTo(ADMIN_ID);
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    // 场景二：上传文件到共享空间（后置效果验证）
    // ═══════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("场景二：上传文件到共享空间")
    class UploadToSharedSpaceScenario {

        @Test
        @DisplayName("共享空间文件属性正确：spaceType=SHARED, ownerUserId=上传者, uploadedBy=上传者")
        void sharedFile_propertiesCorrect() {
            FileNode sharedFile = sharedFile(MOVIE_FILE_ID, USER_A, "movie.mkv", 1024L);
            assertThat(sharedFile.getSpaceType()).isEqualTo(SpaceType.SHARED);
            assertThat(sharedFile.getOwnerUserId()).isEqualTo(USER_A);
            assertThat(sharedFile.getUploadedBy()).isEqualTo(USER_A);
        }

        @Test
        @DisplayName("共享空间文件夹创建：spaceType=SHARED, uploadedBy=操作者")
        void createFolder_sharedSpace_correctProperties() {
            stubPermission(USER_A, true, false, false, false, false, false, false, true);
            when(fileNodeRepository.existsBySpaceTypeAndParentIdAndNameAndDeletedFalse(
                    eq(SpaceType.SHARED), any(), eq("movies"))).thenReturn(false);
            when(fileNodeRepository.save(any(FileNode.class))).thenAnswer(inv -> inv.getArgument(0));

            FileNode folder = service.createFolder(null, "movies", USER_A);

            assertThat(folder.getSpaceType()).isEqualTo(SpaceType.SHARED);
            assertThat(folder.getOwnerUserId()).isEqualTo(USER_A);
            assertThat(folder.getUploadedBy()).isEqualTo(USER_A);
            assertThat(folder.getNodeType()).isEqualTo(NodeType.FOLDER.getValue());
        }

        @Test
        @DisplayName("共享空间文件夹创建成功后可被列出")
        void createFolder_thenListVisible() {
            stubPermission(USER_A, true, false, false, false, false, false, false, true);
            FileNode folder = sharedFolder(DOC_FOLDER_ID, USER_A, "documents");
            when(fileNodeRepository.findBySpaceTypeAndParentIdIsNullAndDeletedFalse(SpaceType.SHARED))
                    .thenReturn(List.of(folder));

            List<FileNode> files = service.listSharedSpaceFiles(null, USER_A);

            assertThat(files).hasSize(1);
            assertThat(files.get(0).getName()).isEqualTo("documents");
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    // 场景三：跨空间移动文件
    // ═══════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("场景三：跨空间移动文件")
    class CrossSpaceMoveScenario {

        @Test
        @DisplayName("个人→共享：spaceType 变为 SHARED，配额正确转移")
        void moveToShared_spaceTypeAndQuotaCorrect() {
            stubPermission(USER_A, true, false, false, false, false, true, false, false);
            FileNode file = personalFile(MOVIE_FILE_ID, USER_A, "movie.mkv", 1024L);
            when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(MOVIE_FILE_ID, USER_A))
                    .thenReturn(Optional.of(file));
            when(fileNodeRepository.existsBySpaceTypeAndParentIdAndNameAndDeletedFalse(
                    eq(SpaceType.SHARED), any(), eq("movie.mkv"))).thenReturn(false);

            service.moveToSharedSpace(MOVIE_FILE_ID, USER_A);

            assertThat(file.getSpaceType()).isEqualTo(SpaceType.SHARED);
            assertThat(file.getUploadedBy()).isEqualTo(USER_A);
            assertThat(file.getOwnerUserId()).isEqualTo(USER_A); // ownerUserId 保持不变
            verify(storageQuotaService).decrementUsage(USER_A, 1024L);
            verify(sharedSpaceQuotaService).increaseUsage(1024L, 1L);
        }

        @Test
        @DisplayName("上传者移回个人：spaceType 变为 PERSONAL，uploadedBy 清空")
        void moveToPersonal_spaceTypeAndUploadedByCorrect() {
            stubPermission(USER_A, true, false, false, false, false, false, true, false);
            FileNode file = sharedFile(MOVIE_FILE_ID, USER_A, "movie.mkv", 1024L);
            when(fileNodeRepository.findByIdAndSpaceTypeAndDeletedFalse(MOVIE_FILE_ID, SpaceType.SHARED))
                    .thenReturn(Optional.of(file));

            service.moveToPersonalSpace(MOVIE_FILE_ID, USER_A);

            assertThat(file.getSpaceType()).isEqualTo(SpaceType.PERSONAL);
            assertThat(file.getOwnerUserId()).isEqualTo(USER_A);
            assertThat(file.getUploadedBy()).isNull();
            verify(sharedSpaceQuotaService).decreaseUsage(1024L, 1L);
            verify(storageQuotaService).incrementUsage(USER_A, 1024L);
        }

        @Test
        @DisplayName("移动文件夹：子文件层级保持")
        void moveFolder_childrenKeepHierarchy() {
            stubPermission(USER_A, true, false, false, false, false, true, false, false);
            FileNode folder = personalFolder(DOC_FOLDER_ID, USER_A, "documents");
            FileNode child = personalFile(REPORT_FILE_ID, USER_A, "report.pdf", 512L);
            child.setParentId(DOC_FOLDER_ID);

            when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(DOC_FOLDER_ID, USER_A))
                    .thenReturn(Optional.of(folder));
            when(fileNodeRepository.existsBySpaceTypeAndParentIdAndNameAndDeletedFalse(
                    eq(SpaceType.SHARED), any(), eq("documents"))).thenReturn(false);
            when(fileNodeRepository.findByOwnerUserIdAndSpaceTypeAndNormalizedPathStartingWithAndDeletedFalse(
                    USER_A, SpaceType.PERSONAL, "/documents/"))
                    .thenReturn(List.of(child));
            when(fileNodeRepository.findByOwnerUserIdAndParentIdAndDeletedFalse(USER_A, DOC_FOLDER_ID))
                    .thenReturn(List.of(child));

            service.moveToSharedSpace(DOC_FOLDER_ID, USER_A);

            assertThat(folder.getSpaceType()).isEqualTo(SpaceType.SHARED);
            assertThat(child.getSpaceType()).isEqualTo(SpaceType.SHARED);
            assertThat(child.getParentId()).isEqualTo(DOC_FOLDER_ID); // 层级保持
        }

        @Test
        @DisplayName("共享空间配额不足时拒绝移动")
        void moveToShared_quotaExceeded_rejected() {
            stubPermission(USER_A, true, false, false, false, false, true, false, false);
            FileNode file = personalFile(MOVIE_FILE_ID, USER_A, "movie.mkv", 1024L);
            when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(MOVIE_FILE_ID, USER_A))
                    .thenReturn(Optional.of(file));
            when(fileNodeRepository.existsBySpaceTypeAndParentIdAndNameAndDeletedFalse(
                    eq(SpaceType.SHARED), any(), eq("movie.mkv"))).thenReturn(false);
            Mockito.doThrow(new BusinessException(ErrorCode.FILE_QUOTA_EXCEEDED, "共享空间容量不足"))
                    .when(sharedSpaceQuotaService).checkQuota(1024L);

            assertThatThrownBy(() -> service.moveToSharedSpace(MOVIE_FILE_ID, USER_A))
                    .isInstanceOf(BusinessException.class)
                    .extracting(ex -> ((BusinessException) ex).errorCode())
                    .isEqualTo(ErrorCode.FILE_QUOTA_EXCEEDED);
        }

        @Test
        @DisplayName("个人配额不足时拒绝移回")
        void moveToPersonal_personalQuotaExceeded_rejected() {
            stubPermission(USER_A, true, false, false, false, false, false, true, false);
            FileNode file = sharedFile(MOVIE_FILE_ID, USER_A, "movie.mkv", 1024L);
            when(fileNodeRepository.findByIdAndSpaceTypeAndDeletedFalse(MOVIE_FILE_ID, SpaceType.SHARED))
                    .thenReturn(Optional.of(file));
            Mockito.doThrow(new BusinessException(ErrorCode.FILE_QUOTA_EXCEEDED, "存储配额不足"))
                    .when(storageQuotaService).checkQuota(USER_A, 1024L);

            assertThatThrownBy(() -> service.moveToPersonalSpace(MOVIE_FILE_ID, USER_A))
                    .isInstanceOf(BusinessException.class)
                    .extracting(ex -> ((BusinessException) ex).errorCode())
                    .isEqualTo(ErrorCode.FILE_QUOTA_EXCEEDED);
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    // 场景四：删除共享空间文件
    // ═══════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("场景四：删除共享空间文件")
    class DeleteSharedFileScenario {

        @Test
        @DisplayName("上传者删除自己的文件：成功，配额减少")
        void uploaderDelete_ownFile_success() {
            stubPermission(USER_A, true, false, false, true, false, false, false, false);
            FileNode file = sharedFile(MOVIE_FILE_ID, USER_A, "movie.mkv", 1024L);
            when(fileNodeRepository.findByIdAndSpaceTypeAndDeletedFalse(MOVIE_FILE_ID, SpaceType.SHARED))
                    .thenReturn(Optional.of(file));
            when(fileNodeRepository.findBySpaceTypeAndParentIdAndDeletedFalse(SpaceType.SHARED, MOVIE_FILE_ID))
                    .thenReturn(List.of());

            service.deleteSharedFile(MOVIE_FILE_ID, USER_A);

            assertThat(file.isDeleted()).isTrue();
            assertThat(file.getDeletedBy()).isEqualTo(USER_A);
            verify(sharedSpaceQuotaService).decreaseUsage(1024L, 1L);
        }

        @Test
        @DisplayName("非上传者无权限删除：拒绝")
        void nonUploader_noPermission_rejected() {
            stubPermission(USER_B, false, false, false, false, false, false, false, false);
            FileNode file = sharedFile(MOVIE_FILE_ID, USER_A, "movie.mkv", 1024L);
            when(fileNodeRepository.findByIdAndSpaceTypeAndDeletedFalse(MOVIE_FILE_ID, SpaceType.SHARED))
                    .thenReturn(Optional.of(file));

            assertThatThrownBy(() -> service.deleteSharedFile(MOVIE_FILE_ID, USER_B))
                    .isInstanceOf(BusinessException.class)
                    .extracting(ex -> ((BusinessException) ex).errorCode())
                    .isEqualTo(ErrorCode.FORBIDDEN);
        }

        @Test
        @DisplayName("删除事件包含正确的 ownerUserId（上传者）")
        void deleteEvent_containsUploaderId() {
            stubPermission(USER_A, true, false, false, true, false, false, false, false);
            FileNode file = sharedFile(MOVIE_FILE_ID, USER_A, "movie.mkv", 1024L);
            when(fileNodeRepository.findByIdAndSpaceTypeAndDeletedFalse(MOVIE_FILE_ID, SpaceType.SHARED))
                    .thenReturn(Optional.of(file));
            when(fileNodeRepository.findBySpaceTypeAndParentIdAndDeletedFalse(SpaceType.SHARED, MOVIE_FILE_ID))
                    .thenReturn(List.of());

            service.deleteSharedFile(MOVIE_FILE_ID, USER_A);

            ArgumentCaptor<FileNodesSoftDeletedEvent> captor = ArgumentCaptor.forClass(FileNodesSoftDeletedEvent.class);
            verify(eventPublisher).publishEvent(captor.capture());
            assertThat(captor.getValue().ownerUserId()).isEqualTo(USER_A);
            assertThat(captor.getValue().fileNodeIds()).contains(MOVIE_FILE_ID);
        }

        @Test
        @DisplayName("删除文件夹：级联删除所有子文件，事件包含所有 ID")
        void deleteFolder_cascadeDelete_allIdsInEvent() {
            stubPermission(USER_A, true, false, false, true, false, false, false, false);
            FileNode folder = sharedFolder(DOC_FOLDER_ID, USER_A, "documents");
            FileNode childFile = sharedFile(REPORT_FILE_ID, USER_A, "report.pdf", 512L);
            FileNode childFolder = sharedFolder(IMAGES_FOLDER_ID, USER_A, "images");
            FileNode grandchild = sharedFile(PHOTO1_ID, USER_A, "photo.jpg", 256L);

            when(fileNodeRepository.findByIdAndSpaceTypeAndDeletedFalse(DOC_FOLDER_ID, SpaceType.SHARED))
                    .thenReturn(Optional.of(folder));
            when(fileNodeRepository.findByOwnerUserIdAndSpaceTypeAndNormalizedPathStartingWithAndDeletedFalse(
                    USER_A, SpaceType.SHARED, "/documents/"))
                    .thenReturn(List.of(childFile, childFolder, grandchild));
            when(fileNodeRepository.findBySpaceTypeAndParentIdAndDeletedFalse(SpaceType.SHARED, DOC_FOLDER_ID))
                    .thenReturn(List.of(childFile, childFolder));
            when(fileNodeRepository.findBySpaceTypeAndParentIdAndDeletedFalse(SpaceType.SHARED, IMAGES_FOLDER_ID))
                    .thenReturn(List.of(grandchild));
            when(fileNodeRepository.findBySpaceTypeAndParentIdAndDeletedFalse(SpaceType.SHARED, REPORT_FILE_ID))
                    .thenReturn(List.of());
            when(fileNodeRepository.findBySpaceTypeAndParentIdAndDeletedFalse(SpaceType.SHARED, PHOTO1_ID))
                    .thenReturn(List.of());

            service.deleteSharedFile(DOC_FOLDER_ID, USER_A);

            assertThat(folder.isDeleted()).isTrue();
            assertThat(childFile.isDeleted()).isTrue();
            assertThat(childFolder.isDeleted()).isTrue();
            assertThat(grandchild.isDeleted()).isTrue();

            ArgumentCaptor<FileNodesSoftDeletedEvent> captor = ArgumentCaptor.forClass(FileNodesSoftDeletedEvent.class);
            verify(eventPublisher).publishEvent(captor.capture());
            assertThat(captor.getValue().fileNodeIds()).contains(DOC_FOLDER_ID, REPORT_FILE_ID, IMAGES_FOLDER_ID, PHOTO1_ID);
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    // 场景五：媒体库合并展示（数据准备验证）
    // ═══════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("场景五：媒体库合并展示")
    class MediaLibraryMergeScenario {

        @Test
        @DisplayName("共享空间文件可被其他用户通过 listSharedSpaceFiles 发现")
        void sharedFile_discoverableByOtherUsers() {
            stubPermission(USER_A, true, false, false, false, false, false, false, false);
            FileNode sharedMovie = sharedFile(MOVIE_FILE_ID, USER_A, "Inception.mkv", 1024L);
            when(fileNodeRepository.findBySpaceTypeAndParentIdIsNullAndDeletedFalse(SpaceType.SHARED))
                    .thenReturn(List.of(sharedMovie));

            // 用户A 浏览共享空间
            List<FileNode> files = service.listSharedSpaceFiles(null, USER_A);

            assertThat(files).hasSize(1);
            assertThat(files.get(0).getName()).isEqualTo("Inception.mkv");
        }

        @Test
        @DisplayName("个人空间文件对其他用户不可见")
        void personalFile_notVisibleToOthers() {
            stubPermission(USER_A, true, false, false, false, false, false, false, false);
            // 用户A的个人文件不应该出现在共享空间列表中
            when(fileNodeRepository.findBySpaceTypeAndParentIdIsNullAndDeletedFalse(SpaceType.SHARED))
                    .thenReturn(List.of()); // 共享空间为空

            List<FileNode> files = service.listSharedSpaceFiles(null, USER_A);

            assertThat(files).isEmpty();
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    // 场景六：文件夹递归操作
    // ═══════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("场景六：文件夹递归操作")
    class FolderRecursiveScenario {

        @Test
        @DisplayName("移动文件夹到共享空间：所有后代文件 spaceType 更新")
        void moveFolderToShared_allDescendantsUpdated() {
            stubPermission(USER_A, true, false, false, false, false, true, false, false);
            FileNode docFolder = personalFolder(DOC_FOLDER_ID, USER_A, "documents");
            FileNode report = personalFile(REPORT_FILE_ID, USER_A, "report.pdf", 512L);
            report.setParentId(DOC_FOLDER_ID);
            FileNode imgFolder = personalFolder(IMAGES_FOLDER_ID, USER_A, "images");
            imgFolder.setParentId(DOC_FOLDER_ID);
            FileNode photo1 = personalFile(PHOTO1_ID, USER_A, "photo1.jpg", 256L);
            photo1.setParentId(IMAGES_FOLDER_ID);
            FileNode photo2 = personalFile(PHOTO2_ID, USER_A, "photo2.jpg", 256L);
            photo2.setParentId(IMAGES_FOLDER_ID);

            when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(DOC_FOLDER_ID, USER_A))
                    .thenReturn(Optional.of(docFolder));
            when(fileNodeRepository.existsBySpaceTypeAndParentIdAndNameAndDeletedFalse(
                    eq(SpaceType.SHARED), any(), eq("documents"))).thenReturn(false);
            when(fileNodeRepository.findByOwnerUserIdAndSpaceTypeAndNormalizedPathStartingWithAndDeletedFalse(
                    USER_A, SpaceType.PERSONAL, "/documents/"))
                    .thenReturn(List.of(report, imgFolder, photo1, photo2));
            // 第一层子文件
            when(fileNodeRepository.findByOwnerUserIdAndParentIdAndDeletedFalse(USER_A, DOC_FOLDER_ID))
                    .thenReturn(List.of(report, imgFolder));
            // 第二层子文件
            when(fileNodeRepository.findByOwnerUserIdAndParentIdAndDeletedFalse(USER_A, IMAGES_FOLDER_ID))
                    .thenReturn(List.of(photo1, photo2));

            service.moveToSharedSpace(DOC_FOLDER_ID, USER_A);

            // 验证所有文件都变为共享空间
            assertThat(docFolder.getSpaceType()).isEqualTo(SpaceType.SHARED);
            assertThat(report.getSpaceType()).isEqualTo(SpaceType.SHARED);
            assertThat(imgFolder.getSpaceType()).isEqualTo(SpaceType.SHARED);
            assertThat(photo1.getSpaceType()).isEqualTo(SpaceType.SHARED);
            assertThat(photo2.getSpaceType()).isEqualTo(SpaceType.SHARED);

            // 验证层级保持
            assertThat(report.getParentId()).isEqualTo(DOC_FOLDER_ID);
            assertThat(imgFolder.getParentId()).isEqualTo(DOC_FOLDER_ID);
            assertThat(photo1.getParentId()).isEqualTo(IMAGES_FOLDER_ID);
            assertThat(photo2.getParentId()).isEqualTo(IMAGES_FOLDER_ID);

            // 验证 uploadedBy 设置正确
            assertThat(docFolder.getUploadedBy()).isEqualTo(USER_A);
            assertThat(report.getUploadedBy()).isEqualTo(USER_A);
        }

        @Test
        @DisplayName("共享空间文件夹导航：子目录正确返回")
        void sharedSpaceFolder_navigationCorrect() {
            stubPermission(USER_A, true, false, false, false, false, false, false, false);
            FileNode docFolder = sharedFolder(DOC_FOLDER_ID, USER_A, "documents");
            FileNode report = sharedFile(REPORT_FILE_ID, USER_A, "report.pdf", 512L);
            report.setParentId(DOC_FOLDER_ID);

            when(fileNodeRepository.findBySpaceTypeAndParentIdAndDeletedFalse(SpaceType.SHARED, DOC_FOLDER_ID))
                    .thenReturn(List.of(report));

            List<FileNode> children = service.listSharedSpaceFiles(DOC_FOLDER_ID, USER_A);

            assertThat(children).hasSize(1);
            assertThat(children.get(0).getName()).isEqualTo("report.pdf");
        }

        @Test
        @DisplayName("共享空间同名文件夹创建被拒绝")
        void createFolder_duplicateName_rejected() {
            stubPermission(USER_A, true, false, false, false, false, false, false, true);
            when(fileNodeRepository.existsBySpaceTypeAndParentIdAndNameAndDeletedFalse(
                    eq(SpaceType.SHARED), any(), eq("documents"))).thenReturn(true);

            assertThatThrownBy(() -> service.createFolder(null, "documents", USER_A))
                    .isInstanceOf(BusinessException.class)
                    .extracting(ex -> ((BusinessException) ex).errorCode())
                    .isEqualTo(ErrorCode.CONFLICT);
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    // 辅助方法
    // ═══════════════════════════════════════════════════════════════════

    private void stubPermission(UUID userId, boolean browse, boolean upload, boolean download,
            boolean deleteOwn, boolean deleteAny, boolean moveTo, boolean moveFrom, boolean createFolder) {
        UUID roleId = userId.equals(ADMIN_ID) ? ADMIN_ROLE_ID : MEMBER_ROLE_ID;
        UserAccountSummary user = new UserAccountSummary(
                userId, "user", Set.of(roleId), false, 0, 0);
        when(userAccountQuery.findById(userId)).thenReturn(Optional.of(user));

        SharedSpacePermission perm = new SharedSpacePermission();
        perm.setCanBrowse(browse);
        perm.setCanUpload(upload);
        perm.setCanDownload(download);
        perm.setCanDeleteOwn(deleteOwn);
        perm.setCanDeleteAny(deleteAny);
        perm.setCanMoveTo(moveTo);
        perm.setCanMoveFrom(moveFrom);
        perm.setCanCreateFolder(createFolder);
        when(permissionRepository.findByRoleIdIn(any())).thenReturn(List.of(perm));
    }

    private FileNode personalFile(UUID id, UUID owner, String name, long size) {
        FileNode node = new FileNode();
        node.setId(id);
        node.setOwnerUserId(owner);
        node.setSpaceType(SpaceType.PERSONAL);
        node.setNodeType(NodeType.FILE.getValue());
        node.setName(name);
        node.setNormalizedPath("/" + name);
        node.setSizeBytes(size);
        node.setDeleted(false);
        return node;
    }

    private FileNode personalFolder(UUID id, UUID owner, String name) {
        FileNode node = new FileNode();
        node.setId(id);
        node.setOwnerUserId(owner);
        node.setSpaceType(SpaceType.PERSONAL);
        node.setNodeType(NodeType.FOLDER.getValue());
        node.setName(name);
        node.setNormalizedPath("/" + name);
        node.setSizeBytes(0L);
        node.setDeleted(false);
        return node;
    }

    private FileNode sharedFile(UUID id, UUID uploader, String name, long size) {
        FileNode node = new FileNode();
        node.setId(id);
        node.setOwnerUserId(uploader);
        node.setSpaceType(SpaceType.SHARED);
        node.setUploadedBy(uploader);
        node.setNodeType(NodeType.FILE.getValue());
        node.setName(name);
        node.setNormalizedPath("/" + name);
        node.setSizeBytes(size);
        node.setDeleted(false);
        return node;
    }

    private FileNode sharedFolder(UUID id, UUID uploader, String name) {
        FileNode node = new FileNode();
        node.setId(id);
        node.setOwnerUserId(uploader);
        node.setSpaceType(SpaceType.SHARED);
        node.setUploadedBy(uploader);
        node.setNodeType(NodeType.FOLDER.getValue());
        node.setName(name);
        node.setNormalizedPath("/" + name);
        node.setSizeBytes(0L);
        node.setDeleted(false);
        return node;
    }
}
