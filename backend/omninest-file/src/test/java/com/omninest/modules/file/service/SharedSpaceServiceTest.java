package com.omninest.modules.file.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.config.ConfigValueProvider;
import com.omninest.common.enums.ErrorCode;
import com.omninest.modules.file.domain.NodeType;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.common.error.BusinessException;
import com.omninest.common.user.UserAccountQuery;
import com.omninest.common.user.UserAccountSummary;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.SharedSpacePermission;
import com.omninest.modules.file.event.FileNodesSoftDeletedEvent;
import com.omninest.modules.file.repository.FileNodePermissionRepository;
import com.omninest.modules.file.repository.FileNodeRepository;
import com.omninest.modules.file.repository.ShareLinkRepository;
import com.omninest.modules.file.repository.SharedSpacePermissionRepository;
import com.omninest.modules.quota.service.StorageQuotaService;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.Mockito;
import org.springframework.context.ApplicationEventPublisher;

/**
 * 共享空间服务测试。
 *
 * @author OmniNest
 */
class SharedSpaceServiceTest {

    private static final UUID USER_A = UUID.fromString("11111111-1111-1111-1111-111111111111");
    private static final UUID USER_B = UUID.fromString("22222222-2222-2222-2222-222222222222");
    private static final UUID ROLE_ID = UUID.fromString("33333333-3333-3333-3333-333333333333");
    private static final UUID FILE_ID = UUID.fromString("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
    private static final UUID FOLDER_ID = UUID.fromString("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");
    private static final UUID CHILD_FILE_ID = UUID.fromString("cccccccc-cccc-cccc-cccc-cccccccccccc");

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

    private SharedSpaceService service;

    @BeforeEach
    void setUp() {
        // 默认共享空间启用
        when(configValueProvider.findByKey("shared_space.enabled"))
                .thenReturn(Optional.of("true"));
        service = new SharedSpaceService(
                fileNodeRepository, permissionRepository, sharedSpaceQuotaService,
                storageQuotaService, userAccountQuery, shareLinkRepository,
                fileNodePermissionRepository, configValueProvider, eventPublisher
        );
    }

    // ── moveToSharedSpace ──────────────────────────────────────────────

    @Nested
    @DisplayName("moveToSharedSpace()")
    class MoveToSharedSpaceTests {

        @Test
        @DisplayName("正常移动：spaceType 变为 SHARED，parentId 清空")
        void moveToSharedSpace_normalFile_updatesFields() {
            stubPermission(USER_A, true, false, false, false, false, true, false, false);
            FileNode file = personalFile(FILE_ID, USER_A, "movie.mkv", 1024L);
            when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(FILE_ID, USER_A))
                    .thenReturn(Optional.of(file));
            when(fileNodeRepository.existsBySpaceTypeAndParentIdAndNameAndDeletedFalse(
                    eq(SpaceType.SHARED), any(), eq("movie.mkv"))).thenReturn(false);

            service.moveToSharedSpace(FILE_ID, USER_A);

            assertThat(file.getSpaceType()).isEqualTo(SpaceType.SHARED);
            assertThat(file.getUploadedBy()).isEqualTo(USER_A);
            assertThat(file.getParentId()).isNull();
            assertThat(file.getOwnerUserId()).isEqualTo(USER_A);
            verify(fileNodeRepository).save(file);
        }

        @Test
        @DisplayName("正常移动：个人配额减少，共享配额增加")
        void moveToSharedSpace_updatesQuota() {
            stubPermission(USER_A, true, false, false, false, false, true, false, false);
            FileNode file = personalFile(FILE_ID, USER_A, "movie.mkv", 2048L);
            when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(FILE_ID, USER_A))
                    .thenReturn(Optional.of(file));
            when(fileNodeRepository.existsBySpaceTypeAndParentIdAndNameAndDeletedFalse(
                    eq(SpaceType.SHARED), any(), eq("movie.mkv"))).thenReturn(false);

            service.moveToSharedSpace(FILE_ID, USER_A);

            verify(storageQuotaService).decrementUsage(USER_A, 2048L);
            verify(sharedSpaceQuotaService).increaseUsage(2048L, 1L);
        }

        @Test
        @DisplayName("共享空间配额不足时抛出异常")
        void moveToSharedSpace_quotaExceeded_throws() {
            stubPermission(USER_A, true, false, false, false, false, true, false, false);
            FileNode file = personalFile(FILE_ID, USER_A, "movie.mkv", 1024L);
            when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(FILE_ID, USER_A))
                    .thenReturn(Optional.of(file));
            when(fileNodeRepository.existsBySpaceTypeAndParentIdAndNameAndDeletedFalse(
                    eq(SpaceType.SHARED), any(), eq("movie.mkv"))).thenReturn(false);
            Mockito.doThrow(new BusinessException(ErrorCode.FILE_QUOTA_EXCEEDED, "共享空间容量不足"))
                    .when(sharedSpaceQuotaService).checkQuota(1024L);

            assertThatThrownBy(() -> service.moveToSharedSpace(FILE_ID, USER_A))
                    .isInstanceOf(BusinessException.class)
                    .extracting(ex -> ((BusinessException) ex).errorCode())
                    .isEqualTo(ErrorCode.FILE_QUOTA_EXCEEDED);
        }

        @Test
        @DisplayName("移动时撤销关联的分享链接和权限")
        void moveToSharedSpace_revokesShareLinksAndPermissions() {
            stubPermission(USER_A, true, false, false, false, false, true, false, false);
            FileNode file = personalFile(FILE_ID, USER_A, "movie.mkv", 1024L);
            when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(FILE_ID, USER_A))
                    .thenReturn(Optional.of(file));
            when(fileNodeRepository.existsBySpaceTypeAndParentIdAndNameAndDeletedFalse(
                    eq(SpaceType.SHARED), any(), eq("movie.mkv"))).thenReturn(false);

            service.moveToSharedSpace(FILE_ID, USER_A);

            verify(shareLinkRepository).disableByResourceId(eq(FILE_ID), any());
            verify(fileNodePermissionRepository).deleteByFileNodeId(FILE_ID);
        }

        @Test
        @DisplayName("同名冲突时抛出 CONFLICT")
        void moveToSharedSpace_nameConflict_throws() {
            stubPermission(USER_A, true, false, false, false, false, true, false, false);
            FileNode file = personalFile(FILE_ID, USER_A, "movie.mkv", 1024L);
            when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(FILE_ID, USER_A))
                    .thenReturn(Optional.of(file));
            when(fileNodeRepository.existsBySpaceTypeAndParentIdAndNameAndDeletedFalse(
                    eq(SpaceType.SHARED), any(), eq("movie.mkv"))).thenReturn(true);

            assertThatThrownBy(() -> service.moveToSharedSpace(FILE_ID, USER_A))
                    .isInstanceOf(BusinessException.class)
                    .extracting(ex -> ((BusinessException) ex).errorCode())
                    .isEqualTo(ErrorCode.CONFLICT);
        }

        @Test
        @DisplayName("文件夹移动：递归更新子文件，保留层级结构")
        void moveToSharedSpace_folder_movesChildren() {
            stubPermission(USER_A, true, false, false, false, false, true, false, false);
            FileNode folder = personalFolder(FOLDER_ID, USER_A, "movies");
            FileNode child = personalFile(CHILD_FILE_ID, USER_A, "movie.mkv", 1024L);
            child.setParentId(FOLDER_ID);

            when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(FOLDER_ID, USER_A))
                    .thenReturn(Optional.of(folder));
            when(fileNodeRepository.existsBySpaceTypeAndParentIdAndNameAndDeletedFalse(
                    eq(SpaceType.SHARED), any(), eq("movies"))).thenReturn(false);
            when(fileNodeRepository.findByOwnerUserIdAndSpaceTypeAndNormalizedPathStartingWithAndDeletedFalse(
                    USER_A, SpaceType.PERSONAL, "/movies/"))
                    .thenReturn(List.of(child));
            when(fileNodeRepository.findByOwnerUserIdAndParentIdAndDeletedFalse(USER_A, FOLDER_ID))
                    .thenReturn(List.of(child));

            service.moveToSharedSpace(FOLDER_ID, USER_A);

            assertThat(folder.getSpaceType()).isEqualTo(SpaceType.SHARED);
            assertThat(child.getSpaceType()).isEqualTo(SpaceType.SHARED);
            assertThat(child.getUploadedBy()).isEqualTo(USER_A);
            assertThat(child.getParentId()).isEqualTo(FOLDER_ID);  // 保留层级结构
        }

        @Test
        @DisplayName("嵌套目录移入共享根：子树规范化路径按新父级重写")
        void moveToSharedSpace_nestedFolder_rewritesDescendantPaths() {
            stubPermission(USER_A, true, false, false, false, false, true, false, false);
            FileNode folder = personalFolder(FOLDER_ID, USER_A, "movies");
            folder.setNormalizedPath("/archive/movies");
            FileNode child = personalFile(CHILD_FILE_ID, USER_A, "movie.mkv", 1024L);
            child.setParentId(FOLDER_ID);
            child.setNormalizedPath("/archive/movies/movie.mkv");

            when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(FOLDER_ID, USER_A))
                    .thenReturn(Optional.of(folder));
            when(fileNodeRepository.existsBySpaceTypeAndParentIdAndNameAndDeletedFalse(
                    eq(SpaceType.SHARED), any(), eq("movies"))).thenReturn(false);
            when(fileNodeRepository.findByOwnerUserIdAndSpaceTypeAndNormalizedPathStartingWithAndDeletedFalse(
                    USER_A, SpaceType.PERSONAL, "/archive/movies/"))
                    .thenReturn(List.of(child));
            when(fileNodeRepository.findBySpaceTypeAndParentIdAndDeletedFalse(SpaceType.SHARED, FOLDER_ID))
                    .thenReturn(List.of(child));
            // 子树重写读的是目标空间：后代已被 batchMoveChildrenToShared 翻成 SHARED。
            when(fileNodeRepository.findBySpaceTypeAndNormalizedPathStartingWithOrderById(
                    eq(SpaceType.SHARED), eq("/archive/movies/"), any()))
                    .thenReturn(new org.springframework.data.domain.PageImpl<>(List.of(child)));

            service.moveToSharedSpace(FOLDER_ID, USER_A);

            assertThat(folder.getNormalizedPath()).isEqualTo("/movies");
            assertThat(child.getNormalizedPath()).isEqualTo("/movies/movie.mkv");
        }

        @Test
        @DisplayName("无权限时抛出 FORBIDDEN")
        void moveToSharedSpace_noPermission_throws() {
            stubPermission(USER_A, false, false, false, false, false, false, false, false);
            FileNode file = personalFile(FILE_ID, USER_A, "movie.mkv", 1024L);
            when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(FILE_ID, USER_A))
                    .thenReturn(Optional.of(file));

            assertThatThrownBy(() -> service.moveToSharedSpace(FILE_ID, USER_A))
                    .isInstanceOf(BusinessException.class)
                    .extracting(ex -> ((BusinessException) ex).errorCode())
                    .isEqualTo(ErrorCode.FORBIDDEN);
        }
    }

    // ── moveToPersonalSpace ────────────────────────────────────────────

    @Nested
    @DisplayName("moveToPersonalSpace()")
    class MoveToPersonalSpaceTests {

        @Test
        @DisplayName("上传者移回自己的文件：spaceType 变为 PERSONAL，uploadedBy 清空")
        void moveToPersonalSpace_normalFile_updatesFields() {
            stubPermission(USER_A, true, false, false, false, false, false, true, false);
            FileNode file = sharedFile(FILE_ID, USER_A, "movie.mkv", 1024L);
            when(fileNodeRepository.findByIdAndSpaceTypeAndDeletedFalse(FILE_ID, SpaceType.SHARED))
                    .thenReturn(Optional.of(file));

            service.moveToPersonalSpace(FILE_ID, USER_A);

            assertThat(file.getSpaceType()).isEqualTo(SpaceType.PERSONAL);
            assertThat(file.getOwnerUserId()).isEqualTo(USER_A);
            assertThat(file.getUploadedBy()).isNull();
            assertThat(file.getParentId()).isNull();
        }

        @Test
        @DisplayName("上传者移回：共享配额减少，个人配额增加")
        void moveToPersonalSpace_updatesQuota() {
            stubPermission(USER_A, true, false, false, false, false, false, true, false);
            FileNode file = sharedFile(FILE_ID, USER_A, "movie.mkv", 2048L);
            when(fileNodeRepository.findByIdAndSpaceTypeAndDeletedFalse(FILE_ID, SpaceType.SHARED))
                    .thenReturn(Optional.of(file));

            service.moveToPersonalSpace(FILE_ID, USER_A);

            verify(sharedSpaceQuotaService).decreaseUsage(2048L, 1L);
            verify(storageQuotaService).incrementUsage(USER_A, 2048L);
        }

        @Test
        @DisplayName("个人根目录已有同名节点时拒绝移回，避免两棵子树共用同一前缀")
        void moveToPersonalSpace_rejectsWhenPersonalRootHasSameName() {
            stubPermission(USER_A, true, false, false, false, false, false, true, false);
            FileNode file = sharedFile(FILE_ID, USER_A, "Reader", 1024L);
            when(fileNodeRepository.findByIdAndSpaceTypeAndDeletedFalse(FILE_ID, SpaceType.SHARED))
                    .thenReturn(Optional.of(file));
            when(fileNodeRepository.existsByOwnerUserIdAndSpaceTypeAndParentIdIsNullAndNameAndDeletedFalse(
                    USER_A, SpaceType.PERSONAL, "Reader"))
                    .thenReturn(true);

            assertThatThrownBy(() -> service.moveToPersonalSpace(FILE_ID, USER_A))
                    .isInstanceOf(BusinessException.class)
                    .extracting(ex -> ((BusinessException) ex).errorCode())
                    .isEqualTo(ErrorCode.CONFLICT);
            assertThat(file.getSpaceType()).isEqualTo(SpaceType.SHARED);
        }

        @Test
        @DisplayName("个人配额不足时抛出异常")
        void moveToPersonalSpace_quotaExceeded_throws() {
            stubPermission(USER_A, true, false, false, false, false, false, true, false);
            FileNode file = sharedFile(FILE_ID, USER_A, "movie.mkv", 1024L);
            when(fileNodeRepository.findByIdAndSpaceTypeAndDeletedFalse(FILE_ID, SpaceType.SHARED))
                    .thenReturn(Optional.of(file));
            Mockito.doThrow(new BusinessException(ErrorCode.FILE_QUOTA_EXCEEDED, "存储配额不足"))
                    .when(storageQuotaService).checkQuota(USER_A, 1024L);

            assertThatThrownBy(() -> service.moveToPersonalSpace(FILE_ID, USER_A))
                    .isInstanceOf(BusinessException.class)
                    .extracting(ex -> ((BusinessException) ex).errorCode())
                    .isEqualTo(ErrorCode.FILE_QUOTA_EXCEEDED);
        }
    }

    // ── deleteSharedFile ───────────────────────────────────────────────

    @Nested
    @DisplayName("deleteSharedFile()")
    class DeleteSharedFileTests {

        @Test
        @DisplayName("上传者删除自己的文件：成功")
        void deleteSharedFile_uploaderCanDelete() {
            stubPermission(USER_A, true, false, false, true, false, false, false, false);
            FileNode file = sharedFile(FILE_ID, USER_A, "movie.mkv", 1024L);
            when(fileNodeRepository.findByIdAndSpaceTypeAndDeletedFalse(FILE_ID, SpaceType.SHARED))
                    .thenReturn(Optional.of(file));
            when(fileNodeRepository.findBySpaceTypeAndParentIdAndDeletedFalse(SpaceType.SHARED, FILE_ID))
                    .thenReturn(List.of());

            service.deleteSharedFile(FILE_ID, USER_A);

            assertThat(file.isDeleted()).isTrue();
            assertThat(file.getDeletedBy()).isEqualTo(USER_A);
            verify(sharedSpaceQuotaService).decreaseUsage(1024L, 1L);
        }

        @Test
        @DisplayName("非上传者无权限删除：抛出 FORBIDDEN")
        void deleteSharedFile_nonUploader_noPermission_throws() {
            stubPermission(USER_B, false, false, false, false, false, false, false, false);
            FileNode file = sharedFile(FILE_ID, USER_A, "movie.mkv", 1024L);
            when(fileNodeRepository.findByIdAndSpaceTypeAndDeletedFalse(FILE_ID, SpaceType.SHARED))
                    .thenReturn(Optional.of(file));

            assertThatThrownBy(() -> service.deleteSharedFile(FILE_ID, USER_B))
                    .isInstanceOf(BusinessException.class)
                    .extracting(ex -> ((BusinessException) ex).errorCode())
                    .isEqualTo(ErrorCode.FORBIDDEN);
        }

        @Test
        @DisplayName("管理员删除他人文件：成功")
        void deleteSharedFile_adminCanDelete() {
            stubPermission(USER_B, true, false, false, false, true, false, false, false);
            FileNode file = sharedFile(FILE_ID, USER_A, "movie.mkv", 1024L);
            when(fileNodeRepository.findByIdAndSpaceTypeAndDeletedFalse(FILE_ID, SpaceType.SHARED))
                    .thenReturn(Optional.of(file));
            when(fileNodeRepository.findBySpaceTypeAndParentIdAndDeletedFalse(SpaceType.SHARED, FILE_ID))
                    .thenReturn(List.of());

            service.deleteSharedFile(FILE_ID, USER_B);

            assertThat(file.isDeleted()).isTrue();
            assertThat(file.getDeletedBy()).isEqualTo(USER_B);
        }

        @Test
        @DisplayName("删除时发布事件，ownerUserId 为上传者")
        void deleteSharedFile_publishesEventWithUploaderId() {
            stubPermission(USER_A, true, false, false, true, false, false, false, false);
            FileNode file = sharedFile(FILE_ID, USER_A, "movie.mkv", 1024L);
            when(fileNodeRepository.findByIdAndSpaceTypeAndDeletedFalse(FILE_ID, SpaceType.SHARED))
                    .thenReturn(Optional.of(file));
            when(fileNodeRepository.findBySpaceTypeAndParentIdAndDeletedFalse(SpaceType.SHARED, FILE_ID))
                    .thenReturn(List.of());

            service.deleteSharedFile(FILE_ID, USER_A);

            ArgumentCaptor<FileNodesSoftDeletedEvent> captor = ArgumentCaptor.forClass(FileNodesSoftDeletedEvent.class);
            verify(eventPublisher).publishEvent(captor.capture());
            assertThat(captor.getValue().ownerUserId()).isEqualTo(USER_A);
            assertThat(captor.getValue().fileNodeIds()).contains(FILE_ID);
        }

        @Test
        @DisplayName("删除文件夹：级联删除子文件")
        void deleteSharedFile_folder_cascadesToChildren() {
            stubPermission(USER_A, true, false, false, true, false, false, false, false);
            FileNode folder = sharedFolder(FOLDER_ID, USER_A, "movies");
            FileNode child = sharedFile(CHILD_FILE_ID, USER_A, "movie.mkv", 1024L);
            child.setParentId(FOLDER_ID);

            when(fileNodeRepository.findByIdAndSpaceTypeAndDeletedFalse(FOLDER_ID, SpaceType.SHARED))
                    .thenReturn(Optional.of(folder));
            when(fileNodeRepository.findByOwnerUserIdAndSpaceTypeAndNormalizedPathStartingWithAndDeletedFalse(
                    USER_A, SpaceType.PERSONAL, "/movies/"))
                    .thenReturn(List.of(child));
            when(fileNodeRepository.findBySpaceTypeAndParentIdAndDeletedFalse(SpaceType.SHARED, FOLDER_ID))
                    .thenReturn(List.of(child));
            when(fileNodeRepository.findBySpaceTypeAndParentIdAndDeletedFalse(SpaceType.SHARED, CHILD_FILE_ID))
                    .thenReturn(List.of());

            service.deleteSharedFile(FOLDER_ID, USER_A);

            assertThat(folder.isDeleted()).isTrue();
            assertThat(child.isDeleted()).isTrue();
        }
    }

    // ── createFolder ───────────────────────────────────────────────────

    @Nested
    @DisplayName("createFolder()")
    class CreateFolderTests {

        @Test
        @DisplayName("正常创建：spaceType=SHARED，uploadedBy=操作者")
        void createFolder_success() {
            stubPermission(USER_A, true, false, false, false, false, false, false, true);
            when(fileNodeRepository.existsBySpaceTypeAndParentIdAndNameAndDeletedFalse(
                    eq(SpaceType.SHARED), any(), eq("movies"))).thenReturn(false);
            when(fileNodeRepository.save(any(FileNode.class))).thenAnswer(inv -> inv.getArgument(0));

            FileNode result = service.createFolder(null, "movies", USER_A);

            assertThat(result.getSpaceType()).isEqualTo(SpaceType.SHARED);
            assertThat(result.getOwnerUserId()).isEqualTo(USER_A);
            assertThat(result.getUploadedBy()).isEqualTo(USER_A);
            assertThat(result.getNodeType()).isEqualTo(NodeType.FOLDER.getValue());
            assertThat(result.getName()).isEqualTo("movies");
            assertThat(result.getNormalizedPath()).isEqualTo("/movies");
        }

        @Test
        @DisplayName("同名冲突：抛出 CONFLICT")
        void createFolder_nameConflict_throws() {
            stubPermission(USER_A, true, false, false, false, false, false, false, true);
            when(fileNodeRepository.existsBySpaceTypeAndParentIdAndNameAndDeletedFalse(
                    eq(SpaceType.SHARED), any(), eq("movies"))).thenReturn(true);

            assertThatThrownBy(() -> service.createFolder(null, "movies", USER_A))
                    .isInstanceOf(BusinessException.class)
                    .extracting(ex -> ((BusinessException) ex).errorCode())
                    .isEqualTo(ErrorCode.CONFLICT);
        }
    }

    // ── validatePermission ─────────────────────────────────────────────

    @Nested
    @DisplayName("validatePermission()")
    class ValidatePermissionTests {

        @Test
        @DisplayName("用户不存在：抛出 UNAUTHORIZED")
        void validatePermission_userNotFound_throws() {
            when(userAccountQuery.findById(USER_A)).thenReturn(Optional.empty());

            assertThatThrownBy(() -> service.validatePermission(USER_A, SharedSpacePermission.Action.CAN_BROWSE))
                    .isInstanceOf(BusinessException.class)
                    .extracting(ex -> ((BusinessException) ex).errorCode())
                    .isEqualTo(ErrorCode.UNAUTHORIZED);
        }

        @Test
        @DisplayName("用户无角色：抛出 FORBIDDEN")
        void validatePermission_noRole_throws() {
            UserAccountSummary user = new UserAccountSummary(USER_A, "user", Set.of(), false, 0, 0);
            when(userAccountQuery.findById(USER_A)).thenReturn(Optional.of(user));

            assertThatThrownBy(() -> service.validatePermission(USER_A, SharedSpacePermission.Action.CAN_BROWSE))
                    .isInstanceOf(BusinessException.class)
                    .extracting(ex -> ((BusinessException) ex).errorCode())
                    .isEqualTo(ErrorCode.FORBIDDEN);
        }

        @Test
        @DisplayName("权限不足：抛出 FORBIDDEN")
        void validatePermission_notAllowed_throws() {
            stubPermission(USER_A, false, false, false, false, false, false, false, false);

            assertThatThrownBy(() -> service.validatePermission(USER_A, SharedSpacePermission.Action.CAN_UPLOAD))
                    .isInstanceOf(BusinessException.class)
                    .extracting(ex -> ((BusinessException) ex).errorCode())
                    .isEqualTo(ErrorCode.FORBIDDEN);
        }
    }

    // ── calculateRestoreSubtreeStats ──────────────────────────────────

    @Nested
    @DisplayName("calculateRestoreSubtreeStats()")
    class CalculateRestoreSubtreeStatsTests {

        @Test
        @DisplayName("文件节点按自身字节计一个文件")
        void fileNodeUsesOwnSize() {
            FileNode file = sharedFile(FILE_ID, USER_A, "movie.mkv", 2048L);

            SharedSpaceService.SubtreeStats stats = service.calculateRestoreSubtreeStats(file);

            assertThat(stats.totalBytes()).isEqualTo(2048L);
            assertThat(stats.fileCount()).isEqualTo(1L);
        }

        @Test
        @DisplayName("目录节点汇总子树内已删除文件，不按目录创建者过滤")
        void folderNodeAggregatesDeletedFilesInSpace() {
            FileNode folder = sharedFolder(FOLDER_ID, USER_A, "movies");
            when(fileNodeRepository.sumDeletedFilesUnderPathInSpace(SpaceType.SHARED, "/movies/"))
                    .thenReturn(List.<Object[]>of(new Object[]{4096L, 3L}));

            SharedSpaceService.SubtreeStats stats = service.calculateRestoreSubtreeStats(folder);

            assertThat(stats.totalBytes()).isEqualTo(4096L);
            assertThat(stats.fileCount()).isEqualTo(3L);
        }
    }

    // ── Helpers ────────────────────────────────────────────────────────

    @Nested
    @DisplayName("canBrowse()：跨模块可见性布尔量")
    class CanBrowseTests {

        @Test
        @DisplayName("空间开启且角色授予 CAN_BROWSE 时为 true")
        void canBrowseTrueForPermittedMember() {
            stubPermission(USER_A, true, false, false, false, false, false, false, false);

            assertThat(service.canBrowse(USER_A)).isTrue();
        }

        @Test
        @DisplayName("角色未授予 CAN_BROWSE 时返回 false，不像 validatePermission 那样抛异常")
        void canBrowseFalseWithoutBrowsePermission() {
            stubPermission(USER_A, false, true, true, false, false, false, false, false);

            assertThat(service.canBrowse(USER_A)).isFalse();
        }

        @Test
        @DisplayName("共享空间关闭时一律不可见，即使角色有权限")
        void canBrowseFalseWhenSpaceDisabled() {
            stubPermission(USER_A, true, true, true, true, true, true, true, true);
            when(configValueProvider.findByKey("shared_space.enabled"))
                    .thenReturn(Optional.of("false"));

            assertThat(service.canBrowse(USER_A)).isFalse();
        }

        @Test
        @DisplayName("用户不存在时返回 false，不判未授权")
        void canBrowseFalseForUnknownUser() {
            when(userAccountQuery.findById(USER_A)).thenReturn(Optional.empty());

            assertThat(service.canBrowse(USER_A)).isFalse();
        }
    }

    /**
     * 为用户设置共享空间权限。
     * 每次调用都会覆盖该用户的权限配置。
     */
    private void stubPermission(UUID userId,
            boolean browse, boolean upload, boolean download,
            boolean deleteOwn, boolean deleteAny,
            boolean moveTo, boolean moveFrom, boolean createFolder) {
        UserAccountSummary user = new UserAccountSummary(
                userId, "user", Set.of(ROLE_ID), false, 0, 0);
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
