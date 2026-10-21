package com.omninest.modules.file.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.cache.ReadThroughCache;
import com.omninest.common.security.CredentialCipher;
import com.omninest.common.user.UserAccountQuery;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.NodeType;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.repository.FileNodeRepository;
import com.omninest.modules.file.repository.FileShareRecipientRepository;
import com.omninest.modules.file.repository.ShareLinkRepository;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.security.crypto.password.PasswordEncoder;

/**
 * 文件夹级联共享测试。
 *
 * @author OmniNest
 */
class FileShareServiceTest {

    private static final UUID OWNER_ID = UUID.fromString("a1a1a1a1-0000-0000-0000-000000000001");
    private static final UUID FOLDER_ID = UUID.fromString("a1a1a1a1-0000-0000-0000-000000000002");
    private static final UUID CHILD_ID = UUID.fromString("a1a1a1a1-0000-0000-0000-000000000003");

    private final FileNodeRepository fileNodeRepository = mock(FileNodeRepository.class);
    private final FilePermissionService filePermissionService = mock(FilePermissionService.class);
    private final FileNodeSupport fileNodeSupport = mock(FileNodeSupport.class);
    private final FileSyncEventWriter syncEventWriter = mock(FileSyncEventWriter.class);
    private final FileShareService service = new FileShareService(
            fileNodeRepository,
            mock(ShareLinkRepository.class),
            mock(FileShareRecipientRepository.class),
            mock(PasswordEncoder.class),
            filePermissionService,
            mock(UserAccountQuery.class),
            fileNodeSupport,
            syncEventWriter,
            mock(ReadThroughCache.class),
            mock(CredentialCipher.class)
    );

    @Test
    @DisplayName("级联共享只匹配子孙路径，不误伤同名前缀兄弟节点")
    void toggleSharedRecursive_matchesOnlyDescendants() {
        FileNode folder = node(FOLDER_ID, "docs", "/docs", NodeType.FOLDER.getValue());
        FileNode child = node(CHILD_ID, "a.txt", "/docs/a.txt", NodeType.FILE.getValue());
        when(fileNodeSupport.findOwnedNode(OWNER_ID, FOLDER_ID)).thenReturn(folder);
        when(fileNodeRepository.findByOwnerUserIdAndSpaceTypeAndNormalizedPathStartingWithAndDeletedFalse(
                eq(OWNER_ID), eq(SpaceType.PERSONAL), any())).thenReturn(List.of(child));

        service.toggleSharedRecursive(OWNER_ID, FOLDER_ID, true);

        // 前缀必须带尾斜杠：/docs 不能连带命中 /docs_2026 与 /docs.pdf
        verify(fileNodeRepository)
                .findByOwnerUserIdAndSpaceTypeAndNormalizedPathStartingWithAndDeletedFalse(
                        OWNER_ID, SpaceType.PERSONAL, "/docs/");
        assertThat(child.isShared()).isTrue();
        assertThat(folder.isShared()).isTrue();
    }

    @Test
    @DisplayName("取消级联共享时只清理子树内的自定义权限")
    void toggleSharedRecursive_unshareClearsOnlySubtreePermissions() {
        FileNode folder = node(FOLDER_ID, "docs", "/docs", NodeType.FOLDER.getValue());
        FileNode child = node(CHILD_ID, "a.txt", "/docs/a.txt", NodeType.FILE.getValue());
        when(fileNodeSupport.findOwnedNode(OWNER_ID, FOLDER_ID)).thenReturn(folder);
        when(fileNodeRepository.findByOwnerUserIdAndSpaceTypeAndNormalizedPathStartingWithAndDeletedFalse(
                eq(OWNER_ID), eq(SpaceType.PERSONAL), eq("/docs/"))).thenReturn(List.of(child));

        service.toggleSharedRecursive(OWNER_ID, FOLDER_ID, false);

        verify(filePermissionService).clearPermissionsBatch(List.of(CHILD_ID, FOLDER_ID));
    }

    private FileNode node(UUID id, String name, String path, String nodeType) {
        FileNode node = new FileNode();
        node.setId(id);
        node.setOwnerUserId(OWNER_ID);
        node.setSpaceType(SpaceType.PERSONAL);
        node.setNodeType(nodeType);
        node.setName(name);
        node.setNormalizedPath(path);
        node.setSizeBytes(0L);
        node.setDeleted(false);
        return node;
    }
}
