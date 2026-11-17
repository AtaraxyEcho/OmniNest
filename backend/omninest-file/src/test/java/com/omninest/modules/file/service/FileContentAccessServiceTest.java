package com.omninest.modules.file.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.FilePurgeState;
import com.omninest.modules.file.domain.NodeType;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.dto.FileContentResource;
import com.omninest.modules.file.repository.FileNodeRepository;
import com.omninest.modules.file.repository.FileObjectRepository;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.core.io.FileSystemResource;

/**
 * 本地媒体令牌读取时复核测试。
 *
 * <p>令牌在 2 小时有效期内不再等同于"仍有权限"：分享撤销、成员降权、空间变化或
 * 文件进入清理流程后，已发地址必须在读取时被拒。</p>
 *
 * @author OmniNest
 */
class FileContentAccessServiceTest {

    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID MEMBER_ID = UUID.fromString("10000000-0000-0000-0000-000000000002");
    private static final UUID FILE_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");
    private static final FileContentResource RESOURCE = new FileContentResource(
            new FileSystemResource("movie.mkv"), "movie.mkv", 1024L, "video/x-matroska");

    private final FileContentProvider provider = mock(FileContentProvider.class);
    private final FileNodeRepository fileNodeRepository = mock(FileNodeRepository.class);
    private final FileObjectRepository fileObjectRepository = mock(FileObjectRepository.class);
    private final LocalContentAccessTokenService tokenService =
            mock(LocalContentAccessTokenService.class);
    private final SharedSpaceService sharedSpaceService = mock(SharedSpaceService.class);
    private final FileShareRecipientAccessService shareRecipientAccessService =
            mock(FileShareRecipientAccessService.class);
    private final FileContentAccessService service = new FileContentAccessService(
            List.of(provider),
            fileNodeRepository,
            fileObjectRepository,
            tokenService,
            sharedSpaceService,
            shareRecipientAccessService
    );

    @Test
    @DisplayName("所有者自己的令牌在有效期内正常读取")
    void ownerGrantStillReads() {
        FileNode node = file(SpaceType.PERSONAL, OWNER_ID);
        grant(OWNER_ID, SpaceType.PERSONAL);
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(FILE_ID, OWNER_ID))
                .thenReturn(Optional.of(node));
        when(provider.supports(node)).thenReturn(true);
        when(provider.providerType()).thenReturn("LOCAL_FILESYSTEM");
        when(provider.findRangeResource(node)).thenReturn(Optional.of(RESOURCE));

        assertThat(service.openPublicLocalResource("token").fileName()).isEqualTo("movie.mkv");
    }

    @Test
    @DisplayName("定向分享被撤销后，已发地址在有效期内也必须失效")
    void revokedRecipientShareIsRejected() {
        FileNode node = file(SpaceType.PERSONAL, OWNER_ID);
        grant(MEMBER_ID, SpaceType.PERSONAL);
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(FILE_ID, OWNER_ID))
                .thenReturn(Optional.of(node));
        when(shareRecipientAccessService.canAccessRecipientNode(MEMBER_ID, node)).thenReturn(false);

        assertThatThrownBy(() -> service.openPublicLocalResource("token"))
                .isInstanceOf(BusinessException.class)
                .extracting(ex -> ((BusinessException) ex).errorCode())
                .isEqualTo(ErrorCode.FORBIDDEN);
    }

    @Test
    @DisplayName("共享空间成员失去下载位后，已发地址不再可读")
    void demotedSharedMemberIsRejected() {
        FileNode node = file(SpaceType.SHARED, OWNER_ID);
        grant(MEMBER_ID, SpaceType.SHARED);
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(FILE_ID, OWNER_ID))
                .thenReturn(Optional.of(node));
        when(sharedSpaceService.canDownload(MEMBER_ID)).thenReturn(false);

        assertThatThrownBy(() -> service.openPublicLocalResource("token"))
                .isInstanceOf(BusinessException.class)
                .extracting(ex -> ((BusinessException) ex).errorCode())
                .isEqualTo(ErrorCode.FORBIDDEN);
    }

    @Test
    @DisplayName("共享空间成员仍具备下载位时继续可读")
    void sharedMemberWithPermissionStillReads() {
        FileNode node = file(SpaceType.SHARED, OWNER_ID);
        grant(MEMBER_ID, SpaceType.SHARED);
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(FILE_ID, OWNER_ID))
                .thenReturn(Optional.of(node));
        when(sharedSpaceService.canDownload(MEMBER_ID)).thenReturn(true);
        when(provider.supports(node)).thenReturn(true);
        when(provider.providerType()).thenReturn("LOCAL_FILESYSTEM");
        when(provider.findRangeResource(node)).thenReturn(Optional.of(RESOURCE));

        assertThat(service.openPublicLocalResource("token").sizeBytes()).isEqualTo(1024L);
    }

    @Test
    @DisplayName("文件换空间后旧地址按授权失效处理")
    void spaceMismatchIsRejected() {
        FileNode node = file(SpaceType.SHARED, OWNER_ID);
        grant(OWNER_ID, SpaceType.PERSONAL);
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(FILE_ID, OWNER_ID))
                .thenReturn(Optional.of(node));

        assertThatThrownBy(() -> service.openPublicLocalResource("token"))
                .isInstanceOf(BusinessException.class)
                .extracting(ex -> ((BusinessException) ex).errorCode())
                .isEqualTo(ErrorCode.FORBIDDEN);
    }

    @Test
    @DisplayName("文件进入永久删除流程后拒绝继续读")
    void purgingFileIsRejected() {
        FileNode node = file(SpaceType.PERSONAL, OWNER_ID);
        node.setPurgeState(FilePurgeState.QUEUED);
        grant(OWNER_ID, SpaceType.PERSONAL);
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(FILE_ID, OWNER_ID))
                .thenReturn(Optional.of(node));

        assertThatThrownBy(() -> service.openPublicLocalResource("token"))
                .isInstanceOf(BusinessException.class)
                .extracting(ex -> ((BusinessException) ex).errorCode())
                .isEqualTo(ErrorCode.FILE_LIFECYCLE_CONFLICT);
    }

    private void grant(UUID requesterUserId, SpaceType spaceType) {
        when(tokenService.requireGrant("token")).thenReturn(
                new LocalContentAccessTokenService.AccessGrant(
                        OWNER_ID,
                        FILE_ID,
                        requesterUserId,
                        spaceType,
                        java.time.Instant.now().plusSeconds(3600)
                ));
    }

    private FileNode file(SpaceType spaceType, UUID owner) {
        FileNode node = new FileNode();
        node.setId(FILE_ID);
        node.setNodeType(NodeType.FILE.getValue());
        node.setSpaceType(spaceType);
        node.setOwnerUserId(owner);
        node.setName("movie.mkv");
        node.setSizeBytes(1024L);
        return node;
    }
}
