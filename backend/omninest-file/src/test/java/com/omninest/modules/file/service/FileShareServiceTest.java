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
import com.omninest.modules.file.domain.ShareLink;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.dto.CreateShareLinkRequest;
import com.omninest.modules.file.repository.FileNodeRepository;
import com.omninest.modules.file.repository.FileShareRecipientRepository;
import com.omninest.modules.file.repository.ShareLinkRepository;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.Pageable;
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
    private final ShareLinkRepository shareLinkRepository = mock(ShareLinkRepository.class);
    private final FilePermissionService filePermissionService = mock(FilePermissionService.class);
    private final FileNodeSupport fileNodeSupport = mock(FileNodeSupport.class);
    private final FileSyncEventWriter syncEventWriter = mock(FileSyncEventWriter.class);
    private final CredentialCipher credentialCipher = mock(CredentialCipher.class);
    private final FileShareService service = new FileShareService(
            fileNodeRepository,
            shareLinkRepository,
            mock(FileShareRecipientRepository.class),
            mock(PasswordEncoder.class),
            filePermissionService,
            mock(UserAccountQuery.class),
            fileNodeSupport,
            syncEventWriter,
            mock(ReadThroughCache.class),
            credentialCipher
    );

    @Test
    @DisplayName("级联共享只匹配子孙路径，不误伤同名前缀兄弟节点")
    void toggleSharedRecursive_matchesOnlyDescendants() {
        FileNode folder = node(FOLDER_ID, "docs", "/docs", NodeType.FOLDER.getValue());
        when(fileNodeSupport.findOwnedNode(OWNER_ID, FOLDER_ID)).thenReturn(folder);

        service.toggleSharedRecursive(OWNER_ID, FOLDER_ID, true);

        // 前缀必须带尾斜杠：/docs 不能连带命中 /docs_2026 与 /docs.pdf
        verify(fileNodeRepository).updateSharedByPathPrefix(
                eq(OWNER_ID),
                eq(SpaceType.PERSONAL),
                eq("/docs/"),
                eq(true),
                any(Instant.class),
                any(Instant.class));
        assertThat(folder.isShared()).isTrue();
    }

    @Test
    @DisplayName("分享资源类型以节点真实类型写入，客户端传反不会改变语义")
    void createShareUsesNodeTypeAsResourceType() {
        FileNode file = node(FOLDER_ID, "报告.pdf", "/报告.pdf", NodeType.FILE.getValue());
        when(fileNodeSupport.findActiveNode(OWNER_ID, FOLDER_ID)).thenReturn(file);
        when(credentialCipher.encrypt(any())).thenReturn("cipher");
        when(shareLinkRepository.save(any(ShareLink.class))).thenAnswer(invocation -> {
            ShareLink link = invocation.getArgument(0);
            link.setId(UUID.randomUUID());
            link.setCreatedAt(Instant.now());
            return link;
        });
        when(fileNodeRepository.findByIdAndOwnerUserId(FOLDER_ID, OWNER_ID))
                .thenReturn(Optional.of(file));

        var created = service.createShare(OWNER_ID, new CreateShareLinkRequest(
                FOLDER_ID,
                NodeType.FOLDER.getValue(),
                null,
                false,
                null,
                null,
                List.of()
        ));

        assertThat(created.resourceType()).isEqualTo(NodeType.FILE.getValue());
    }

    @Test
    @DisplayName("取消级联共享时只清理子树内的自定义权限")
    void toggleSharedRecursive_unshareClearsOnlySubtreePermissions() {
        FileNode folder = node(FOLDER_ID, "docs", "/docs", NodeType.FOLDER.getValue());
        when(fileNodeSupport.findOwnedNode(OWNER_ID, FOLDER_ID)).thenReturn(folder);
        when(fileNodeRepository.findActiveIdsByPathPrefix(
                eq(OWNER_ID), eq(SpaceType.PERSONAL), eq("/docs/"), any(Pageable.class)))
                .thenReturn(new PageImpl<>(List.of(CHILD_ID)));

        service.toggleSharedRecursive(OWNER_ID, FOLDER_ID, false);

        verify(filePermissionService).clearPermissionsBatch(List.of(CHILD_ID));
        verify(filePermissionService).clearPermissions(FOLDER_ID);
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
