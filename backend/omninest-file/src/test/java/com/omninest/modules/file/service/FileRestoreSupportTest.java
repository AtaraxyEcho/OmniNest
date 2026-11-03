package com.omninest.modules.file.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.NodeType;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.repository.FileNodeRepository;
import com.omninest.modules.file.repository.FileNodeSubtreeQueryRepository;
import java.time.Instant;
import java.util.Collection;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

/**
 * 回收站恢复子树收集的单元测试。
 *
 * <p>锁定 DELETION_BATCH_SKEW 与同层同名去重三道过滤：任一过滤失效，恢复文件夹时都会
 * 把不该复活的节点写回未删除状态，事务提交撞击活动路径唯一索引并返回 HTTP 500。</p>
 *
 * @author OmniNest
 */
class FileRestoreSupportTest {

    private static final UUID OWNER = UUID.fromString("30000000-0000-0000-0000-000000000001");
    private static final UUID ROOT_ID = UUID.fromString("30000000-0000-0000-0000-000000000002");
    private static final Instant ROOT_DELETED_AT = Instant.parse("2026-11-02T10:00:00Z");

    private FileNodeRepository fileNodeRepository;
    private FileNodeSubtreeQueryRepository subtreeQueryRepository;
    private FileRestoreSupport support;

    @BeforeEach
    void setUp() {
        fileNodeRepository = mock(FileNodeRepository.class);
        subtreeQueryRepository = mock(FileNodeSubtreeQueryRepository.class);
        support = new FileRestoreSupport(fileNodeRepository, subtreeQueryRepository);
    }

    @Test
    void sameNameDeletedSiblingsOnlyCollectTheNewestOne() {
        FileNode root = deletedFolder(ROOT_ID, null, "docs", ROOT_DELETED_AT);
        FileNode newer = deletedFile(UUID.randomUUID(), ROOT_ID, "a.txt", ROOT_DELETED_AT);
        FileNode older = deletedFile(UUID.randomUUID(), ROOT_ID, "a.txt", ROOT_DELETED_AT.plusMillis(200));
        // 仓储按 deletedAt 倒序返回：同层最新一次删除排在最前。
        when(subtreeQueryRepository.findRestorableChildrenByParentIds(SpaceType.PERSONAL, List.of(ROOT_ID)))
                .thenReturn(List.of(newer, older));

        List<FileNode> collected = support.deletedSubtreeNodes(root);

        // 两条同名记录同时复活必然撞击活动唯一索引，这正是文件夹恢复 500 的根因。
        assertThat(collected).extracting(FileNode::getId).containsExactly(newer.getId());
    }

    @Test
    void childrenDeletedBeforeBatchWindowAreNotRevivedWithFolder() {
        FileNode root = deletedFolder(ROOT_ID, null, "docs", ROOT_DELETED_AT);
        FileNode batchChild = deletedFile(UUID.randomUUID(), ROOT_ID, "in-batch.txt",
                ROOT_DELETED_AT.minusMillis(100));
        FileNode historicalChild = deletedFile(UUID.randomUUID(), ROOT_ID, "old.txt",
                ROOT_DELETED_AT.minusSeconds(2));
        when(subtreeQueryRepository.findRestorableChildrenByParentIds(SpaceType.PERSONAL, List.of(ROOT_ID)))
                .thenReturn(List.of(batchChild, historicalChild));

        List<FileNode> collected = support.deletedSubtreeNodes(root);

        // 超过 500ms 删除批次偏差窗口的历史旧文件属于独立删除，不随目录复活。
        assertThat(collected).extracting(FileNode::getId).containsExactly(batchChild.getId());
    }

    @Test
    void activeSiblingNameCollisionIsSkippedAndBfsKeepsDescending() {
        FileNode root = deletedFolder(ROOT_ID, null, "docs", ROOT_DELETED_AT);
        FileNode subFolder = deletedFolder(UUID.randomUUID(), ROOT_ID, "sub", ROOT_DELETED_AT);
        FileNode conflictChild = deletedFile(UUID.randomUUID(), ROOT_ID, "plan.pdf", ROOT_DELETED_AT);
        FileNode activeTwin = activeFile(UUID.randomUUID(), ROOT_ID, "plan.pdf");
        FileNode grandFile = deletedFile(UUID.randomUUID(), subFolder.getId(), "inside.txt", ROOT_DELETED_AT);

        // BFS 每层各查一次：第一层返回子目录与同名记录，第二层返回孙文件。
        when(subtreeQueryRepository.findRestorableChildrenByParentIds(any(), any()))
                .thenReturn(List.of(subFolder, conflictChild), List.of(grandFile));
        when(subtreeQueryRepository.findActiveChildrenByParentIds(any(), any()))
                .thenReturn(List.of(activeTwin), List.of());

        List<FileNode> collected = support.deletedSubtreeNodes(root);

        // 与活动同名节点冲突的已删记录必须跳过，其余子树仍按父先于子逐层收集。
        assertThat(collected).extracting(FileNode::getId)
                .containsExactly(subFolder.getId(), grandFile.getId());
        verify(subtreeQueryRepository).findActiveChildrenByParentIds(SpaceType.PERSONAL, List.of(ROOT_ID));
        ArgumentCaptor<Collection<UUID>> frontierCaptor = ArgumentCaptor.forClass(Collection.class);
        verify(subtreeQueryRepository, times(2))
                .findRestorableChildrenByParentIds(eq(SpaceType.PERSONAL), frontierCaptor.capture());
        assertThat(frontierCaptor.getAllValues().get(0)).containsExactly(ROOT_ID);
        assertThat(frontierCaptor.getAllValues().get(1)).containsExactly(subFolder.getId());
    }

    private FileNode deletedFolder(UUID id, UUID parentId, String name, Instant deletedAt) {
        FileNode node = baseNode(id, parentId, name, NodeType.FOLDER);
        node.setDeleted(true);
        node.setDeletedAt(deletedAt);
        return node;
    }

    private FileNode deletedFile(UUID id, UUID parentId, String name, Instant deletedAt) {
        FileNode node = baseNode(id, parentId, name, NodeType.FILE);
        node.setDeleted(true);
        node.setDeletedAt(deletedAt);
        return node;
    }

    private FileNode activeFile(UUID id, UUID parentId, String name) {
        return baseNode(id, parentId, name, NodeType.FILE);
    }

    private FileNode baseNode(UUID id, UUID parentId, String name, NodeType nodeType) {
        FileNode node = new FileNode();
        node.setId(id);
        node.setOwnerUserId(OWNER);
        node.setParentId(parentId);
        node.setNodeType(nodeType.getValue());
        node.setName(name);
        node.setNormalizedPath(parentId == null ? "/" + name : "/docs/" + name);
        node.setSpaceType(SpaceType.PERSONAL);
        node.setDeleted(false);
        return node;
    }
}
