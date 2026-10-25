package com.omninest.modules.file.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.NodeType;
import com.omninest.modules.file.domain.ShareLink;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.repository.FileShareRecipientRepository;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * 定向分享接收人授权测试。
 *
 * @author OmniNest
 */
class FileShareRecipientAccessServiceTest {

    private static final UUID RECIPIENT_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID OWNER_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");

    private final FileShareRecipientRepository recipientRepository =
            mock(FileShareRecipientRepository.class);
    private final FileShareRecipientAccessService service =
            new FileShareRecipientAccessService(recipientRepository);

    @Test
    @DisplayName("单文件定向分享允许接收人访问")
    void directFileShareAllowsRecipient() {
        FileNode file = file(UUID.randomUUID(), OWNER_ID, "/docs/report.pdf");
        when(recipientRepository.findActiveFileSharePairs(RECIPIENT_ID, List.of(file.getId())))
                .thenReturn(List.<Object[]>of(new Object[]{file.getId(), OWNER_ID}));
        when(recipientRepository.findActiveFolderShareRoots(RECIPIENT_ID)).thenReturn(List.of());

        assertThat(service.canAccessRecipientNode(RECIPIENT_ID, file)).isTrue();
    }

    @Test
    @DisplayName("被分享文件夹的后代允许接收人访问")
    void folderShareCoversDescendants() {
        FileNode file = file(UUID.randomUUID(), OWNER_ID, "/project/docs/report.pdf");
        ShareLink folderShare = activeFolderShare();
        when(recipientRepository.findActiveFileSharePairs(any(), any())).thenReturn(List.of());
        when(recipientRepository.findActiveFolderShareRoots(RECIPIENT_ID))
                .thenReturn(List.<Object[]>of(new Object[]{folderShare, "/project"}));

        assertThat(service.canAccessRecipientNode(RECIPIENT_ID, file)).isTrue();
    }

    @Test
    @DisplayName("前缀相近的兄弟目录不在分享范围")
    void siblingPrefixIsNotCovered() {
        FileNode file = file(UUID.randomUUID(), OWNER_ID, "/projectX/report.pdf");
        ShareLink folderShare = activeFolderShare();
        when(recipientRepository.findActiveFileSharePairs(any(), any())).thenReturn(List.of());
        when(recipientRepository.findActiveFolderShareRoots(RECIPIENT_ID))
                .thenReturn(List.<Object[]>of(new Object[]{folderShare, "/project"}));

        assertThat(service.canAccessRecipientNode(RECIPIENT_ID, file)).isFalse();
    }

    @Test
    @DisplayName("易主节点不属于分享所有者的授权范围")
    void reassignedNodeIsRejected() {
        UUID newOwner = UUID.randomUUID();
        FileNode file = file(UUID.randomUUID(), newOwner, "/project/report.pdf");
        when(recipientRepository.findActiveFileSharePairs(any(), any())).thenReturn(List.of());
        when(recipientRepository.findActiveFolderShareRoots(RECIPIENT_ID))
                .thenReturn(List.<Object[]>of(new Object[]{activeFolderShare(), "/project"}));

        assertThat(service.canAccessRecipientNode(RECIPIENT_ID, file)).isFalse();
    }

    private ShareLink activeFolderShare() {
        ShareLink link = new ShareLink();
        link.setId(UUID.randomUUID());
        link.setOwnerUserId(OWNER_ID);
        link.setResourceType("FOLDER");
        link.setResourceId(UUID.randomUUID());
        link.setExpiresAt(Instant.now().plusSeconds(3600));
        return link;
    }

    private FileNode file(UUID id, UUID owner, String path) {
        FileNode node = new FileNode();
        node.setId(id);
        node.setOwnerUserId(owner);
        node.setSpaceType(SpaceType.PERSONAL);
        node.setNodeType(NodeType.FILE.getValue());
        node.setName(path.substring(path.lastIndexOf('/') + 1));
        node.setNormalizedPath(path);
        return node;
    }
}
