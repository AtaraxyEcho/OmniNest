package com.omninest.modules.file.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.security.RequestPrincipal;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.FilePermission;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.dto.FileDescriptor;
import com.omninest.modules.file.repository.FileNodeRepository;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;

/**
 * 文件读取权限边界测试：所有者、共享空间成员与历史文件共享三条判据互不越界。
 *
 * @author OmniNest
 */
class FileLifecycleGuardTest {

    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID MEMBER_ID = UUID.fromString("10000000-0000-0000-0000-000000000002");
    private static final RequestPrincipal MEMBER = RequestPrincipal.credential(() -> MEMBER_ID);
    private static final UUID STRANGER_ID = UUID.fromString("10000000-0000-0000-0000-000000000003");
    private static final UUID NODE_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");

    private final FileNodeRepository fileNodeRepository = Mockito.mock(FileNodeRepository.class);
    private final FilePermissionService filePermissionService = Mockito.mock(FilePermissionService.class);
    private final SharedSpaceService sharedSpaceService = Mockito.mock(SharedSpaceService.class);
    private final FileDownloadService fileDownloadService = Mockito.mock(FileDownloadService.class);
    private final FileLifecycleGuard guard =
            new FileLifecycleGuard(fileNodeRepository, filePermissionService, sharedSpaceService,
                    fileDownloadService);

    private FileNode node(SpaceType spaceType, boolean shared) {
        FileNode node = new FileNode();
        node.setId(NODE_ID);
        node.setOwnerUserId(OWNER_ID);
        node.setNodeType("FILE");
        node.setName("song.mp3");
        node.setNormalizedPath("/song.mp3");
        node.setMimeType("audio/mpeg");
        node.setSizeBytes(1024L);
        node.setSpaceType(spaceType);
        node.setShared(shared);
        return node;
    }

    private void givenNode(FileNode node) {
        when(fileNodeRepository.findByIdAndDeletedFalse(NODE_ID)).thenReturn(Optional.of(node));
    }

    @Test
    void ownerReadsOwnNodeWithoutAnyPermissionLookup() {
        givenNode(node(SpaceType.PERSONAL, false));

        FileDescriptor descriptor = guard.requireReadable(OWNER_ID, NODE_ID);

        assertThat(descriptor.id()).isEqualTo(NODE_ID);
        verify(filePermissionService, never()).resolvePermission(any(), any());
        verify(sharedSpaceService, never()).validateBrowsePermission(any());
    }

    /** 共享空间成员按角色矩阵即可读取：这是"能列出却打不开"缺陷的回归锁。 */
    @Test
    void sharedSpaceMemberWithBrowsePermissionReadsOtherMembersNode() {
        givenNode(node(SpaceType.SHARED, false));

        assertThat(guard.requireReadable(MEMBER_ID, NODE_ID).spaceType()).isEqualTo(SpaceType.SHARED);
        verify(sharedSpaceService).validateBrowsePermission(MEMBER_ID);
        verify(filePermissionService, never()).resolvePermission(any(), any());
    }

    /** 无浏览权限或共享空间总开关关闭时被拒：共享空间不是"所有登录用户可读"。 */
    @Test
    void sharedSpaceMemberWithoutBrowsePermissionIsRejected() {
        givenNode(node(SpaceType.SHARED, false));
        doThrow(new BusinessException(ErrorCode.FORBIDDEN, "共享空间已禁用"))
                .when(sharedSpaceService).validateBrowsePermission(STRANGER_ID);

        assertThatThrownBy(() -> guard.requireReadable(STRANGER_ID, NODE_ID))
                .isInstanceOf(BusinessException.class)
                .hasFieldOrPropertyWithValue("errorCode", ErrorCode.FORBIDDEN);
    }

    @Test
    void personalNodeSharedWithUserIsReadableThroughFilePermission() {
        givenNode(node(SpaceType.PERSONAL, true));
        when(filePermissionService.resolvePermission(NODE_ID, MEMBER_ID))
                .thenReturn(FilePermission.readOnly());

        assertThat(guard.requireReadable(MEMBER_ID, NODE_ID).id()).isEqualTo(NODE_ID);
        verify(sharedSpaceService, never()).validateBrowsePermission(any());
    }

    @Test
    void personalNodeWithoutShareOrPermissionIsRejected() {
        givenNode(node(SpaceType.PERSONAL, false));
        when(filePermissionService.resolvePermission(NODE_ID, MEMBER_ID))
                .thenReturn(FilePermission.denyAll());

        assertThatThrownBy(() -> guard.requireReadable(MEMBER_ID, NODE_ID))
                .isInstanceOf(BusinessException.class)
                .hasFieldOrPropertyWithValue("errorCode", ErrorCode.FORBIDDEN);
    }

    /** 节点未共享且无权限记录时，即使历史数据带 shared 标志也必须走 allowView 判定。 */
    @Test
    void sharedFlagWithoutViewPermissionIsRejected() {
        givenNode(node(SpaceType.PERSONAL, true));
        when(filePermissionService.resolvePermission(NODE_ID, MEMBER_ID))
                .thenReturn(new FilePermission(false, true, true, true));

        assertThatThrownBy(() -> guard.requireReadable(MEMBER_ID, NODE_ID))
                .isInstanceOf(BusinessException.class)
                .hasFieldOrPropertyWithValue("errorCode", ErrorCode.FORBIDDEN);
    }

    @Test
    void downloadableUsesDownloadPredicateInsteadOfBrowseOnly() {
        FileNode node = node(SpaceType.SHARED, false);
        when(fileDownloadService.requireDownloadableNode(MEMBER, NODE_ID))
                .thenReturn(node);

        FileDescriptor descriptor = guard.requireDownloadable(MEMBER, NODE_ID);

        assertThat(descriptor.id()).isEqualTo(NODE_ID);
        verify(fileDownloadService).requireDownloadableNode(MEMBER, NODE_ID);
        verify(sharedSpaceService, never()).validateBrowsePermission(any());
    }
}
