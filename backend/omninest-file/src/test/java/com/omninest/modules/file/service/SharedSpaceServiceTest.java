package com.omninest.modules.file.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.config.ConfigValueProvider;
import com.omninest.common.cache.ReadThroughCache;
import com.omninest.common.config.RuntimeConfigCommand;
import com.omninest.common.audit.AdminAuditRecorder;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.sync.UserSyncEventRecorder;
import com.omninest.modules.file.domain.NodeType;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.common.error.BusinessException;
import com.omninest.common.user.UserAccountQuery;
import com.omninest.common.user.UserAccountSummary;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.SharedSpacePermission;
import com.omninest.modules.file.dto.RenameFileNodeRequest;
import com.omninest.modules.file.event.FileNodesSoftDeletedEvent;
import com.omninest.modules.file.repository.FileNodePermissionRepository;
import com.omninest.modules.file.repository.FileMetricsRepository;
import com.omninest.modules.file.repository.FileNodeRepository;
import com.omninest.modules.file.repository.ShareLinkRepository;
import com.omninest.modules.file.repository.SharedSpacePermissionRepository;
import com.omninest.modules.quota.service.StorageQuotaService;
import com.omninest.modules.quota.port.AdminActorVerifier;
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
import org.springframework.data.domain.Pageable;

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
    private final FileMetricsRepository fileMetricsRepository = mock(FileMetricsRepository.class);
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
        // 默认共享空间启用
        when(configValueProvider.findByKey("shared_space.enabled"))
                .thenReturn(Optional.of("true"));
        service = new SharedSpaceService(
                fileNodeRepository, fileMetricsRepository, permissionRepository, sharedSpaceQuotaService,
                storageQuotaService, userAccountQuery, shareLinkRepository,
                fileNodePermissionRepository, configValueProvider, eventPublisher,
                fileIndexSyncService, syncEventRecorder, readThroughCache,
                mock(RuntimeConfigCommand.class), mock(AdminActorVerifier.class),
                mock(AdminAuditRecorder.class)
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

            verify(shareLinkRepository).disableByResourceIdIn(eq(List.of(FILE_ID)), any());
            verify(fileNodePermissionRepository).deleteByFileNodeIdIn(eq(List.of(FILE_ID)));
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
            child.setNormalizedPath("/movies/movie.mkv");

            when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(FOLDER_ID, USER_A))
                    .thenReturn(Optional.of(folder));
            when(fileNodeRepository.existsBySpaceTypeAndParentIdAndNameAndDeletedFalse(
                    eq(SpaceType.SHARED), any(), eq("movies"))).thenReturn(false);
            when(fileNodeRepository.findPersonalSubtreeIncludingDeleted(
                    USER_A, SpaceType.PERSONAL, "/movies/"))
                    .thenReturn(List.of(child));
            service.moveToSharedSpace(FOLDER_ID, USER_A);

            assertThat(folder.getSpaceType()).isEqualTo(SpaceType.SHARED);
            assertThat(child.getSpaceType()).isEqualTo(SpaceType.SHARED);
            assertThat(child.getUploadedBy()).isEqualTo(USER_A);
            assertThat(child.getParentId()).isEqualTo(FOLDER_ID);
        }

        @Test
        @DisplayName("目录内回收站子项随父目录一起迁入共享空间")
        void moveToSharedSpace_movesSoftDeletedDescendants() {
            stubPermission(USER_A, true, false, false, false, false, true, false, false);
            FileNode folder = personalFolder(FOLDER_ID, USER_A, "movies");
            FileNode deletedChild = personalFile(CHILD_FILE_ID, USER_A, "old.mkv", 512L);
            deletedChild.setParentId(FOLDER_ID);
            deletedChild.setNormalizedPath("/movies/old.mkv");
            deletedChild.setDeleted(true);

            when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(FOLDER_ID, USER_A))
                    .thenReturn(Optional.of(folder));
            when(fileNodeRepository.existsBySpaceTypeAndParentIdAndNameAndDeletedFalse(
                    eq(SpaceType.SHARED), any(), eq("movies"))).thenReturn(false);
            when(fileNodeRepository.findPersonalSubtreeIncludingDeleted(
                    USER_A, SpaceType.PERSONAL, "/movies/"))
                    .thenReturn(List.of(deletedChild));

            service.moveToSharedSpace(FOLDER_ID, USER_A);

            assertThat(deletedChild.getSpaceType()).isEqualTo(SpaceType.SHARED);
            assertThat(deletedChild.getUploadedBy()).isEqualTo(USER_A);
            assertThat(deletedChild.getNormalizedPath()).isEqualTo("/movies/old.mkv");
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
            when(fileNodeRepository.findPersonalSubtreeIncludingDeleted(
                    USER_A, SpaceType.PERSONAL, "/archive/movies/"))
                    .thenReturn(List.of(child));
            service.moveToSharedSpace(FOLDER_ID, USER_A);

            assertThat(folder.getNormalizedPath()).isEqualTo("/movies");
            assertThat(child.getNormalizedPath()).isEqualTo("/movies/movie.mkv");
            // 跨空间移动不得再按路径前缀盲扫目标空间：那会把其他用户/成员的同名子树一起改掉。
            verify(fileNodeRepository, never()).findSubtreeBySpaceTypeAfterId(
                    any(), anyString(), any(), any());
        }

        @Test
        @DisplayName("已在共享空间的节点再次移入：拒绝且不重复扣个人配额")
        void moveToSharedSpace_alreadyShared_rejectsWithoutDoubleCharging() {
            stubPermission(USER_A, true, false, false, false, false, true, false, false);
            FileNode already = sharedFile(FOLDER_ID, USER_A, "movie.mkv", 2048L);
            when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(FOLDER_ID, USER_A))
                    .thenReturn(Optional.of(already));

            assertThatThrownBy(() -> service.moveToSharedSpace(FOLDER_ID, USER_A))
                    .isInstanceOf(BusinessException.class)
                    .extracting(exception -> ((BusinessException) exception).errorCode())
                    .isEqualTo(ErrorCode.CONFLICT);

            // 重复移入曾把个人已用空间反复扣到 0 并让共享配额虚增
            verify(storageQuotaService, never()).decrementUsage(any(), Mockito.anyLong());
            verify(sharedSpaceQuotaService, never()).increaseUsage(Mockito.anyLong(), Mockito.anyLong());
        }

        @Test
        @DisplayName("共享文件夹改名：子树路径按主键游标全量重写")
        void renameSharedFile_rewritesWholeSubtreeByCursor() {
            // 上传者改名需要 CAN_DELETE_OWN
            stubPermission(USER_A, true, false, false, true, false, false, false, false);
            FileNode folder = sharedFolder(FOLDER_ID, USER_A, "movies");
            folder.setNormalizedPath("/movies");
            FileNode first = sharedFile(CHILD_FILE_ID, USER_A, "a.mkv", 10L);
            first.setParentId(FOLDER_ID);
            first.setNormalizedPath("/movies/a.mkv");
            FileNode second = sharedFile(UUID.randomUUID(), USER_A, "b.mkv", 10L);
            second.setParentId(FOLDER_ID);
            second.setNormalizedPath("/movies/b.mkv");

            when(fileNodeRepository.findByIdAndSpaceTypeAndDeletedFalse(FOLDER_ID, SpaceType.SHARED))
                    .thenReturn(Optional.of(folder));
            when(fileNodeRepository.existsBySpaceTypeAndParentIdAndNameAndDeletedFalse(
                    eq(SpaceType.SHARED), any(), eq("cinema"))).thenReturn(false);
            // 改写掉的记录不再匹配旧前缀：按 OFFSET 递增翻页会整批跳过未改写的后代，
            // 因此每一批都必须从上一批最大 ID 继续。
            when(fileNodeRepository.findSubtreeBySpaceTypeAfterId(
                    eq(SpaceType.SHARED), eq("/movies/"), any(UUID.class), any(Pageable.class)))
                    .thenReturn(List.of(first))
                    .thenReturn(List.of(second))
                    .thenReturn(List.of());

            service.renameSharedFile(FOLDER_ID, new RenameFileNodeRequest("cinema"), USER_A);

            assertThat(folder.getNormalizedPath()).isEqualTo("/cinema");
            assertThat(first.getNormalizedPath()).isEqualTo("/cinema/a.mkv");
            assertThat(second.getNormalizedPath()).isEqualTo("/cinema/b.mkv");
            ArgumentCaptor<UUID> cursors = ArgumentCaptor.forClass(UUID.class);
            verify(fileNodeRepository, Mockito.times(3)).findSubtreeBySpaceTypeAfterId(
                    eq(SpaceType.SHARED), eq("/movies/"), cursors.capture(), any(Pageable.class));
            assertThat(cursors.getAllValues()).containsExactly(
                    new UUID(0L, 0L), first.getId(), second.getId());
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
            // 换空间后旧公开链接与细粒度授权必须立即失效。
            verify(shareLinkRepository).disableByResourceIdIn(eq(List.of(FILE_ID)), any(Instant.class));
            verify(fileNodePermissionRepository).deleteByFileNodeIdIn(List.of(FILE_ID));
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
        @DisplayName("上传者不能把目录内其他成员上传的文件整体迁入个人空间")
        void moveToPersonalSpace_rejectsOtherUploadersWithoutDeleteAny() {
            stubPermission(USER_A, true, false, false, false, false, false, true, false);
            FileNode folder = sharedFolder(FOLDER_ID, USER_A, "Project");
            FileNode otherUpload = sharedFile(CHILD_FILE_ID, USER_B, "b.txt", 128L);
            otherUpload.setParentId(FOLDER_ID);
            otherUpload.setNormalizedPath("/Project/b.txt");
            when(fileNodeRepository.findByIdAndSpaceTypeAndDeletedFalse(FOLDER_ID, SpaceType.SHARED))
                    .thenReturn(Optional.of(folder));
            when(fileNodeRepository.findSubtreeInSpaceIncludingDeleted(
                    SpaceType.SHARED, "/Project/"))
                    .thenReturn(List.of(otherUpload));

            assertThatThrownBy(() -> service.moveToPersonalSpace(FOLDER_ID, USER_A))
                    .isInstanceOf(BusinessException.class)
                    .extracting(ex -> ((BusinessException) ex).errorCode())
                    .isEqualTo(ErrorCode.FORBIDDEN);

            assertThat(folder.getSpaceType()).isEqualTo(SpaceType.SHARED);
            verify(fileNodeRepository, never()).save(folder);
            verify(storageQuotaService, never()).incrementUsage(any(), Mockito.anyLong());
            verify(sharedSpaceQuotaService, never()).decreaseUsage(Mockito.anyLong(), Mockito.anyLong());
        }

        @Test
        @DisplayName("具有 CAN_DELETE_ANY 的管理员可以整体迁回混合上传者的目录")
        void moveToPersonalSpace_adminCanMoveMixedUploaders() {
            stubPermission(USER_B, true, false, false, false, true, false, false, false);
            FileNode folder = sharedFolder(FOLDER_ID, USER_A, "Project");
            FileNode child = sharedFile(CHILD_FILE_ID, USER_A, "b.txt", 128L);
            child.setParentId(FOLDER_ID);
            child.setNormalizedPath("/Project/b.txt");
            when(fileNodeRepository.findByIdAndSpaceTypeAndDeletedFalse(FOLDER_ID, SpaceType.SHARED))
                    .thenReturn(Optional.of(folder));
            when(fileNodeRepository.findSubtreeInSpaceIncludingDeleted(
                    SpaceType.SHARED, "/Project/"))
                    .thenReturn(List.of(child));

            service.moveToPersonalSpace(FOLDER_ID, USER_B);

            assertThat(child.getSpaceType()).isEqualTo(SpaceType.PERSONAL);
            assertThat(child.getOwnerUserId()).isEqualTo(USER_B);
            assertThat(child.getUploadedBy()).isNull();
            assertThat(child.getNormalizedPath()).isEqualTo("/Project/b.txt");
        }

        @Test
        @DisplayName("目录内回收站子项随父目录迁回个人空间，且不进入索引同步范围")
        void moveToPersonalSpace_movesSoftDeletedDescendant() {
            stubPermission(USER_A, true, false, false, false, false, false, true, false);
            FileNode folder = sharedFolder(FOLDER_ID, USER_A, "Project");
            FileNode deletedChild = sharedFile(CHILD_FILE_ID, USER_A, "old.txt", 128L);
            deletedChild.setParentId(FOLDER_ID);
            deletedChild.setNormalizedPath("/Project/old.txt");
            deletedChild.setDeleted(true);
            when(fileNodeRepository.findByIdAndSpaceTypeAndDeletedFalse(FOLDER_ID, SpaceType.SHARED))
                    .thenReturn(Optional.of(folder));
            when(fileNodeRepository.findSubtreeInSpaceIncludingDeleted(
                    SpaceType.SHARED, "/Project/"))
                    .thenReturn(List.of(deletedChild));

            service.moveToPersonalSpace(FOLDER_ID, USER_A);

            assertThat(deletedChild.isDeleted()).isTrue();
            assertThat(deletedChild.getSpaceType()).isEqualTo(SpaceType.PERSONAL);
            assertThat(deletedChild.getOwnerUserId()).isEqualTo(USER_A);
            assertThat(deletedChild.getNormalizedPath()).isEqualTo("/Project/old.txt");
            verify(fileIndexSyncService).scheduleAfterCommit(USER_A, List.of(FOLDER_ID));
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
            when(fileNodeRepository.findActiveIdsUnderPathInSpace(SpaceType.SHARED, "/movies/"))
                    .thenReturn(List.of(CHILD_FILE_ID));
            when(fileNodeRepository.findAllById(any())).thenReturn(List.of(child));

            service.deleteSharedFile(FOLDER_ID, USER_A);

            assertThat(folder.isDeleted()).isTrue();
            verify(fileNodeRepository).softDeleteSubtreeInSpace(
                    eq(SpaceType.SHARED), eq("/movies/"), any(Instant.class), eq(USER_A));
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
        @DisplayName("父节点是文件：抛出 FILE_PATH_INVALID")
        void createFolder_parentIsFile_throws() {
            UUID parentId = UUID.randomUUID();
            stubPermission(USER_A, true, false, false, false, false, false, false, true);
            when(fileNodeRepository.findByIdAndSpaceTypeAndDeletedFalse(parentId, SpaceType.SHARED))
                    .thenReturn(Optional.of(sharedFile(parentId, USER_A, "movie.mkv", 1024)));

            assertThatThrownBy(() -> service.createFolder(parentId, "sub", USER_A))
                    .isInstanceOf(BusinessException.class)
                    .extracting(ex -> ((BusinessException) ex).errorCode())
                    .isEqualTo(ErrorCode.FILE_PATH_INVALID);
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
