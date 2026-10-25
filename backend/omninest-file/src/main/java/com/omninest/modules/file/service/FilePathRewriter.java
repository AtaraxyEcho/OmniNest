package com.omninest.modules.file.service;

import com.omninest.common.util.LikePatterns;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.NodeType;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.repository.FileNodeRepository;
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

    /**
     * 级联重写子树规范化路径（包含回收站里的子孙）。
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
                    ? fileNodeRepository.findSubtreeBySpaceTypeAfterId(
                            spaceType, prefix, afterId, PageRequest.of(0, REWRITE_BATCH_SIZE))
                    : fileNodeRepository.findPersonalSubtreeAfterId(
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
     * 恢复前按父级当前路径重算整棵恢复子树：祖先链从根到叶，目标节点再按最终父路径落位，
     * 子孙沿用相对后缀整体平移。
     *
     * @param node 待恢复节点
     * @param ancestors 一并恢复的已删除祖先链（从根到叶）
     * @param descendants 随同恢复的已删除子孙
     */
    public void recomputeRestoredPaths(
            FileNode node, List<FileNode> ancestors, List<FileNode> descendants) {
        Map<UUID, FileNode> ancestorById = new LinkedHashMap<>();
        ancestors.forEach(ancestor -> ancestorById.put(ancestor.getId(), ancestor));
        for (FileNode ancestor : ancestors) {
            FileNode restoredParent = ancestor.getParentId() == null
                    ? null
                    : ancestorById.get(ancestor.getParentId());
            String parentPath = restoredParent != null
                    ? restoredParent.getNormalizedPath()
                    : resolveActiveParentPath(ancestor);
            ancestor.setNormalizedPath(joinNodePath(parentPath, ancestor.getName()));
        }
        FileNode restoredParent = node.getParentId() == null ? null : ancestorById.get(node.getParentId());
        String parentPath = restoredParent != null
                ? restoredParent.getNormalizedPath()
                : resolveActiveParentPath(node);
        String oldPath = node.getNormalizedPath();
        String newPath = joinNodePath(parentPath, node.getName());
        node.setNormalizedPath(newPath);
        if (oldPath == null || oldPath.equals(newPath)) {
            return;
        }
        String oldPrefix = oldPath + "/";
        for (FileNode descendant : descendants) {
            String path = descendant.getNormalizedPath();
            if (path != null && path.startsWith(oldPrefix)) {
                descendant.setNormalizedPath(newPath + path.substring(oldPath.length()));
            }
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
