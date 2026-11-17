package com.omninest.modules.file.service;

import com.omninest.common.util.LikePatterns;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.NodeType;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.repository.FileNodeRepository;
import com.omninest.modules.file.repository.FileNodeSubtreeQueryRepository;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Component;

/**
 * 文件树规范化路径改写：目录改名/移动的级联更新与回收站恢复时的路径重算。
 *
 * @author OmniNest
 */
@Component
@RequiredArgsConstructor
public class FilePathRewriter {

    private static final int REWRITE_BATCH_SIZE = 500;

    private final FileNodeRepository fileNodeRepository;
    private final FileNodeSubtreeQueryRepository subtreeQueryRepository;

    /**
     * 级联重写活动子树的规范化路径。
     *
     * <p>只重写 {@code deleted = false} 的节点：回收站节点保留删除时的路径，恢复时由
     * {@code recomputeRestoredPaths} 按 {@code parent_id} 链重算。若把已删节点一并改写，
     * 用户“删除 /docs → 新建 /docs → 改名为 /archive”后，回收站里旧 /docs 的子文件
     * 会被改成 /archive/...，与仍指向旧父目录的 parent_id 彻底脱节。</p>
     *
     * @param ownerUserId 所有者用户 ID（共享空间忽略）
     * @param spaceType 空间类型
     * @param oldPath 变更前根路径
     * @param newPath 变更后根路径
     * @return 路径发生变化且需要重建搜索索引的文件节点 ID
     */
    public List<UUID> rewriteDescendantPaths(
            UUID ownerUserId, SpaceType spaceType, String oldPath, String newPath) {
        if (oldPath == null || oldPath.equals(newPath)) {
            return List.of();
        }
        List<UUID> affectedFileIds = new ArrayList<>();
        String prefix = LikePatterns.escapeSpecials(oldPath + "/");
        UUID afterId = new UUID(0L, 0L);
        while (true) {
            List<FileNode> batch = spaceType == SpaceType.SHARED
                    ? subtreeQueryRepository.findActiveSubtreeBySpaceTypeAfterId(
                            spaceType, prefix, afterId, PageRequest.of(0, REWRITE_BATCH_SIZE))
                    : subtreeQueryRepository.findActivePersonalSubtreeAfterId(
                            ownerUserId, spaceType, prefix, afterId,
                            PageRequest.of(0, REWRITE_BATCH_SIZE));
            if (batch.isEmpty()) {
                return affectedFileIds;
            }
            for (FileNode descendant : batch) {
                descendant.setNormalizedPath(
                        newPath + descendant.getNormalizedPath().substring(oldPath.length()));
                afterId = descendant.getId();
                // 索引只收录文件：文件夹入队只会产生无效的索引任务。
                if (NodeType.FILE.getValue().equals(descendant.getNodeType())) {
                    affectedFileIds.add(descendant.getId());
                }
            }
            fileNodeRepository.saveAll(batch);
        }
    }

    /**
     * 恢复前按父级当前路径重算整棵恢复子树。
     *
     * <p>祖先链从根到叶逐层落位，目标节点按最终父路径落位，子孙再按 {@code parent_id}
     * 找到已重算的父路径逐层拼接。恢复子树来自按 {@code parent_id} 的广度优先收集，
     * 天然满足父在子前，因此这里不再依赖旧字符串前缀——旧前缀可能已被活动目录改名
     * 或回收站历史删除污染。</p>
     *
     * @param node 待恢复节点
     * @param ancestors 一并恢复的已删除祖先链（从根到叶）
     * @param descendants 随同恢复的已删除子孙（父节点先于子节点）
     */
    public void recomputeRestoredPaths(
            FileNode node, List<FileNode> ancestors, List<FileNode> descendants) {
        Map<UUID, FileNode> knownById = new LinkedHashMap<>();
        ancestors.forEach(ancestor -> knownById.put(ancestor.getId(), ancestor));
        for (FileNode ancestor : ancestors) {
            FileNode restoredParent = ancestor.getParentId() == null
                    ? null
                    : knownById.get(ancestor.getParentId());
            String parentPath = restoredParent != null
                    ? restoredParent.getNormalizedPath()
                    : resolveActiveParentPath(ancestor);
            ancestor.setNormalizedPath(joinNodePath(parentPath, ancestor.getName()));
        }
        FileNode restoredParent = node.getParentId() == null ? null : knownById.get(node.getParentId());
        String nodeParentPath = restoredParent != null
                ? restoredParent.getNormalizedPath()
                : resolveActiveParentPath(node);
        node.setNormalizedPath(joinNodePath(nodeParentPath, node.getName()));
        knownById.put(node.getId(), node);

        for (FileNode descendant : descendants) {
            FileNode parent = knownById.get(descendant.getParentId());
            String parentPath = parent != null
                    ? parent.getNormalizedPath()
                    : resolveActiveParentPath(descendant);
            descendant.setNormalizedPath(joinNodePath(parentPath, descendant.getName()));
            knownById.put(descendant.getId(), descendant);
        }
    }

    private String resolveActiveParentPath(FileNode node) {
        if (node.getParentId() == null) {
            return "";
        }
        FileNode parent = node.getSpaceType() == SpaceType.SHARED
                ? fileNodeRepository.findByIdAndSpaceTypeAndDeletedFalse(
                        node.getParentId(), SpaceType.SHARED).orElse(null)
                : fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(
                        node.getParentId(), node.getOwnerUserId()).orElse(null);
        return parent == null ? "" : parent.getNormalizedPath();
    }

    private String joinNodePath(String parentPath, String name) {
        if (parentPath == null || parentPath.isBlank() || "/".equals(parentPath)) {
            return "/" + name;
        }
        return parentPath + "/" + name;
    }
}
