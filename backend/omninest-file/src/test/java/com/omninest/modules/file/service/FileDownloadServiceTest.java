package com.omninest.modules.file.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.NodeType;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.dto.FileDownloadUrlDto;
import com.omninest.modules.file.repository.FileNodeRepository;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * 下载地址权限判定测试。
 *
 * @author OmniNest
 */
class FileDownloadServiceTest {

    private static final UUID USER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID FILE_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");
    private static final FileDownloadUrlDto URL = new FileDownloadUrlDto(
            FILE_ID, "movie.mkv", "https://example.com/signed", Instant.EPOCH);

    private final FileNodeRepository fileNodeRepository = mock(FileNodeRepository.class);
    private final FileContentAccessService fileContentAccessService =
            mock(FileContentAccessService.class);
    private final SharedSpaceService sharedSpaceService = mock(SharedSpaceService.class);
    private final FileShareRecipientAccessService shareRecipientAccessService =
            mock(FileShareRecipientAccessService.class);
    private final FileDownloadService service = new FileDownloadService(
            fileNodeRepository, fileContentAccessService, sharedSpaceService, shareRecipientAccessService);

    @Test
    @DisplayName("共享空间成员凭下载权限取得他人上传文件的地址")
    void sharedMemberCanDownloadOthersFile() {
        FileNode shared = file(SpaceType.SHARED, UUID.randomUUID());
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(FILE_ID, USER_ID))
                .thenReturn(Optional.empty());
        when(fileNodeRepository.findByIdAndDeletedFalse(FILE_ID)).thenReturn(Optional.of(shared));
        when(sharedSpaceService.canDownload(USER_ID)).thenReturn(true);
        when(fileContentAccessService.createDownloadUrl(shared)).thenReturn(URL);

        FileDownloadUrlDto result = service.createDownloadUrl(USER_ID, FILE_ID);

        assertThat(result.downloadUrl()).isEqualTo("https://example.com/signed");
    }

    @Test
    @DisplayName("无下载权限的共享空间成员被拒绝")
    void sharedMemberWithoutPermissionIsRejected() {
        FileNode shared = file(SpaceType.SHARED, UUID.randomUUID());
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(FILE_ID, USER_ID))
                .thenReturn(Optional.empty());
        when(fileNodeRepository.findByIdAndDeletedFalse(FILE_ID)).thenReturn(Optional.of(shared));
        when(sharedSpaceService.canDownload(USER_ID)).thenReturn(false);
        when(shareRecipientAccessService.canAccessRecipientNode(USER_ID, shared)).thenReturn(false);

        assertThatThrownBy(() -> service.createDownloadUrl(USER_ID, FILE_ID))
                .isInstanceOf(BusinessException.class)
                .extracting(ex -> ((BusinessException) ex).errorCode())
                .isEqualTo(ErrorCode.FORBIDDEN);
        verify(fileContentAccessService, never()).createDownloadUrl(any());
    }

    @Test
    @DisplayName("个人空间非所有者按文件不存在处理")
    void personalNonOwnerGetsNotFound() {
        FileNode personal = file(SpaceType.PERSONAL, UUID.randomUUID());
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(FILE_ID, USER_ID))
                .thenReturn(Optional.empty());
        when(fileNodeRepository.findByIdAndDeletedFalse(FILE_ID)).thenReturn(Optional.of(personal));

        assertThatThrownBy(() -> service.createDownloadUrl(USER_ID, FILE_ID))
                .isInstanceOf(BusinessException.class)
                .extracting(ex -> ((BusinessException) ex).errorCode())
                .isEqualTo(ErrorCode.FILE_NOT_FOUND);
    }

    @Test
    @DisplayName("批量签发只保留所有者与可下载共享文件")
    void batchKeepsOwnedAndReadableSharedFiles() {
        UUID ownedId = UUID.randomUUID();
        UUID sharedId = UUID.randomUUID();
        UUID privateOtherId = UUID.randomUUID();
        FileNode owned = file(ownedId, NodeType.FILE.getValue(), SpaceType.PERSONAL, USER_ID);
        FileNode shared = file(sharedId, NodeType.FILE.getValue(), SpaceType.SHARED, UUID.randomUUID());
        FileNode privateOther = file(
                privateOtherId, NodeType.FILE.getValue(), SpaceType.PERSONAL, UUID.randomUUID());
        when(fileNodeRepository.findAllById(any())).thenReturn(List.of(owned, shared, privateOther));
        when(sharedSpaceService.canDownload(USER_ID)).thenReturn(true);
        when(shareRecipientAccessService.filterRecipientAccessible(USER_ID, List.of(owned, shared, privateOther)))
                .thenReturn(Set.of());
        when(fileContentAccessService.createDownloadUrls(List.of(owned, shared)))
                .thenReturn(Map.of(ownedId, URL, sharedId, URL));

        Map<UUID, FileDownloadUrlDto> result = service.createDownloadUrls(
                USER_ID, List.of(ownedId, sharedId, privateOtherId));

        assertThat(result).containsOnlyKeys(ownedId, sharedId);
    }

    @Test
    @DisplayName("批量签发也包含定向分享给当前用户的个人空间文件")
    void batchKeepsRecipientSharedPersonalFiles() {
        UUID ownedId = UUID.randomUUID();
        UUID recipientFileId = UUID.randomUUID();
        FileNode owned = file(ownedId, NodeType.FILE.getValue(), SpaceType.PERSONAL, USER_ID);
        FileNode recipientFile = file(
                recipientFileId, NodeType.FILE.getValue(), SpaceType.PERSONAL, UUID.randomUUID());
        List<FileNode> candidates = List.of(owned, recipientFile);
        when(fileNodeRepository.findAllById(any())).thenReturn(candidates);
        when(shareRecipientAccessService.filterRecipientAccessible(USER_ID, candidates))
                .thenReturn(Set.of(recipientFileId));
        when(fileContentAccessService.createDownloadUrls(candidates))
                .thenReturn(Map.of(ownedId, URL, recipientFileId, URL));

        Map<UUID, FileDownloadUrlDto> result = service.createDownloadUrls(
                USER_ID, List.of(ownedId, recipientFileId));

        assertThat(result).containsOnlyKeys(ownedId, recipientFileId);
    }

    @Test
    @DisplayName("定向分享接收人可直接取得个人空间文件的下载地址")
    void recipientCanDownloadDirectlySharedPersonalFile() {
        FileNode personal = file(SpaceType.PERSONAL, UUID.randomUUID());
        when(fileNodeRepository.findByIdAndDeletedFalse(FILE_ID)).thenReturn(Optional.of(personal));
        when(shareRecipientAccessService.canAccessRecipientNode(USER_ID, personal)).thenReturn(true);
        when(fileContentAccessService.createDownloadUrl(personal)).thenReturn(URL);

        FileDownloadUrlDto result = service.createDownloadUrlForShared(USER_ID, FILE_ID);

        assertThat(result.downloadUrl()).isEqualTo("https://example.com/signed");
    }

    @Test
    @DisplayName("非接收人访问个人空间分享按无权限拒绝")
    void nonRecipientCannotDownloadPersonalShare() {
        FileNode personal = file(SpaceType.PERSONAL, UUID.randomUUID());
        when(fileNodeRepository.findByIdAndDeletedFalse(FILE_ID)).thenReturn(Optional.of(personal));
        when(shareRecipientAccessService.canAccessRecipientNode(USER_ID, personal)).thenReturn(false);

        assertThatThrownBy(() -> service.createDownloadUrlForShared(USER_ID, FILE_ID))
                .isInstanceOf(BusinessException.class)
                .extracting(ex -> ((BusinessException) ex).errorCode())
                .isEqualTo(ErrorCode.FORBIDDEN);
        verify(fileContentAccessService, never()).createDownloadUrl(any());
    }

    @Test
    @DisplayName("普通下载接口也会放行定向分享接收人")
    void recipientCanUseRegularDownloadEndpoint() {
        FileNode personal = file(SpaceType.PERSONAL, UUID.randomUUID());
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(FILE_ID, USER_ID))
                .thenReturn(Optional.empty());
        when(fileNodeRepository.findByIdAndDeletedFalse(FILE_ID)).thenReturn(Optional.of(personal));
        when(shareRecipientAccessService.canAccessRecipientNode(USER_ID, personal)).thenReturn(true);
        when(fileContentAccessService.createDownloadUrl(personal)).thenReturn(URL);

        FileDownloadUrlDto result = service.createDownloadUrl(USER_ID, FILE_ID);

        assertThat(result.downloadUrl()).isEqualTo("https://example.com/signed");
    }

    private FileNode file(SpaceType spaceType, UUID owner) {
        return file(FILE_ID, NodeType.FILE.getValue(), spaceType, owner);
    }

    private FileNode file(UUID id, String nodeType, SpaceType spaceType, UUID owner) {
        FileNode node = new FileNode();
        node.setId(id);
        node.setNodeType(nodeType);
        node.setSpaceType(spaceType);
        node.setOwnerUserId(owner);
        node.setName("movie.mkv");
        node.setSizeBytes(1024L);
        return node;
    }
}
