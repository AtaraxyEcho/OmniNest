package com.omninest.modules.file.service;

import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.ShareLink;
import com.omninest.modules.file.repository.FileShareRecipientRepository;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Collection;
import java.util.HashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 定向分享接收人的内容访问判定。
 *
 * <p>定向分享只写 {@code share_links} 与 {@code file_share_recipients}，不写节点的
 * shared 标记或文件权限，因此下载与预览必须按接收关系授权。除直接分享的单文件外，
 * 被分享文件夹的后代也属于授权范围。</p>
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class FileShareRecipientAccessService {

    private final FileShareRecipientRepository shareRecipientRepository;

    /**
     * 过滤出当前用户可凭定向分享访问的节点。
     *
     * @param userId 当前用户 ID
     * @param nodes 候选节点
     * @return 可访问节点 ID
     */
    @Transactional(readOnly = true)
    public Set<UUID> filterRecipientAccessible(UUID userId, Collection<FileNode> nodes) {
        if (userId == null || nodes == null || nodes.isEmpty()) {
            return Set.of();
        }
        Map<UUID, FileNode> candidatesById = new HashMap<>();
        for (FileNode node : nodes) {
            if (node != null && !node.isDeleted() && !Objects.equals(node.getOwnerUserId(), userId)) {
                candidatesById.put(node.getId(), node);
            }
        }
        if (candidatesById.isEmpty()) {
            return Set.of();
        }

        Set<UUID> accessible = new LinkedHashSet<>();
        addDirectFileShares(userId, candidatesById, accessible);
        addAncestorFolderShares(userId, candidatesById, accessible);
        return accessible;
    }

    /**
     * 判断当前用户是否可凭定向分享访问单个节点。
     *
     * @param userId 当前用户 ID
     * @param node 文件或文件夹节点
     * @return 可访问时为 true
     */
    @Transactional(readOnly = true)
    public boolean canAccessRecipientNode(UUID userId, FileNode node) {
        return node != null && filterRecipientAccessible(userId, List.of(node)).contains(node.getId());
    }

    private void addDirectFileShares(
            UUID userId,
            Map<UUID, FileNode> candidatesById,
            Set<UUID> accessible
    ) {
        List<Object[]> pairs = shareRecipientRepository.findActiveFileSharePairs(
                userId, new ArrayList<>(candidatesById.keySet()));
        for (Object[] pair : pairs) {
            UUID resourceId = (UUID) pair[0];
            UUID ownerUserId = (UUID) pair[1];
            FileNode node = candidatesById.get(resourceId);
            if (node != null && Objects.equals(ownerUserId, node.getOwnerUserId())) {
                accessible.add(resourceId);
            }
        }
    }

    private void addAncestorFolderShares(
            UUID userId,
            Map<UUID, FileNode> candidatesById,
            Set<UUID> accessible
    ) {
        List<Object[]> roots = shareRecipientRepository.findActiveFolderShareRoots(userId);
        Instant now = Instant.now();
        for (Object[] row : roots) {
            ShareLink link = (ShareLink) row[0];
            String rootPath = (String) row[1];
            if (link == null || !isActive(link, now) || rootPath == null || rootPath.isBlank()) {
                continue;
            }
            for (Map.Entry<UUID, FileNode> entry : candidatesById.entrySet()) {
                FileNode node = entry.getValue();
                if (!Objects.equals(link.getOwnerUserId(), node.getOwnerUserId())
                        || node.getNormalizedPath() == null) {
                    continue;
                }
                String path = node.getNormalizedPath();
                if (path.equals(rootPath) || path.startsWith(rootPath + "/")) {
                    accessible.add(entry.getKey());
                }
            }
        }
    }

    private boolean isActive(ShareLink link, Instant now) {
        return link.getDisabledAt() == null
                && (link.getExpiresAt() == null || link.getExpiresAt().isAfter(now));
    }
}
