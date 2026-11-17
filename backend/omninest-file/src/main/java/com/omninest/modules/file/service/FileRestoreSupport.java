package com.omninest.modules.file.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.FilePurgeState;
import com.omninest.modules.file.domain.NodeType;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.repository.FileNodeRepository;
import com.omninest.modules.file.repository.FileNodeSubtreeQueryRepository;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Objects;
import java.util.Set;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

/**
 * 回收站恢复的子树解析与祖先校验支撑。
 *
 * <p>从 {@link FileQueryService} 拆出，避免主服务因批量恢复持续膨胀；
 * 本类只做只读解析与实体标记，不负责事务与事件。</p>
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class FileRestoreSupport {

    /**
     * 目录删除与子节点标记在同一事务内批量写入，时间戳理论上一致；不同数据库/时钟精度
     * 下允许极小偏差。早于该窗口的已删节点视为更早的独立删除，不随目录一起复活。
     */
    private static final Duration DELETION_BATCH_SKEW = Duration.ofMillis(500);

    private final FileNodeRepository fileNodeRepository;
    private final FileNodeSubtreeQueryRepository subtreeQueryRepository;

    /**
     * 按 {@code parent_id} 广度优先收集随该目录一同删除、且可以安全复活的子孙节点。
     *
     * <p>不能按 {@code normalized_path} 前缀收集：同一路径下允许先后删除多个同名文件，
     * 它们同时在回收站共存，前缀收集会把历史上所有曾在该路径下删除过的节点全部置为
     * 未删除，事务提交时直接撞击活动路径唯一索引，导致整个文件夹无法恢复。</p>
     *
     * <p>三级过滤：只收本空间/本所有者的节点；只收删除时间不早于根节点删除批次的节点；
     * 同层同名只保留最新一条，且跳过同目录已存在活动同名节点的记录。</p>
     *
     * @param node 待恢复的根节点
     * @return 可安全复活的子孙节点（父节点先于子节点）
     */
    List<FileNode> deletedSubtreeNodes(FileNode node) {
        if (!NodeType.FOLDER.getValue().equals(node.getNodeType())) {
            return List.of();
        }
        Instant rootDeletedAt = node.getDeletedAt();
        SpaceType spaceType = node.getSpaceType();
        List<FileNode> result = new ArrayList<>();
        List<UUID> frontier = List.of(node.getId());
        while (!frontier.isEmpty()) {
            List<FileNode> children = subtreeQueryRepository.findRestorableChildrenByParentIds(
                    spaceType, frontier);
            if (children.isEmpty()) {
                break;
            }
            Set<String> activeSiblingKeys = new HashSet<>();
            for (FileNode active : subtreeQueryRepository.findActiveChildrenByParentIds(spaceType, frontier)) {
                activeSiblingKeys.add(siblingKey(active));
            }
            Set<String> seenSiblingKeys = new HashSet<>();
            List<UUID> nextFrontier = new ArrayList<>();
            for (FileNode child : children) {
                if (spaceType == SpaceType.PERSONAL
                        && !Objects.equals(child.getOwnerUserId(), node.getOwnerUserId())) {
                    continue;
                }
                // 早于文件夹删除时间单独删掉的历史旧文件不随文件夹整棵复活。
                if (rootDeletedAt != null
                        && child.getDeletedAt() != null
                        && child.getDeletedAt().isBefore(rootDeletedAt.minus(DELETION_BATCH_SKEW))) {
                    continue;
                }
                String key = siblingKey(child);
                // 同目录已有活动同名节点：复活必然撞唯一索引，保留其在回收站的独立状态。
                if (activeSiblingKeys.contains(key) || !seenSiblingKeys.add(key)) {
                    continue;
                }
                result.add(child);
                if (NodeType.FOLDER.getValue().equals(child.getNodeType())) {
                    nextFrontier.add(child.getId());
                }
            }
            frontier = nextFrontier;
        }
        return result;
    }

    private String siblingKey(FileNode node) {
        return node.getParentId() + ":" + node.getName().toLowerCase(Locale.ROOT);
    }

    /**
     * 收集目标节点上方仍处于回收站的祖先链，供恢复时一并还原。
     */
    List<FileNode> collectDeletedAncestors(FileNode node) {
        List<FileNode> ancestors = new ArrayList<>();
        UUID parentId = node.getParentId();
        while (parentId != null) {
            FileNode parent = fileNodeRepository.findById(parentId).orElse(null);
            if (parent == null || !parent.isDeleted()) {
                break;
            }
            if (parent.getSpaceType() != node.getSpaceType()) {
                throw new BusinessException(ErrorCode.FILE_PATH_INVALID, "上级文件夹与当前文件空间不一致");
            }
            if (parent.getSpaceType() == SpaceType.PERSONAL
                    && !Objects.equals(parent.getOwnerUserId(), node.getOwnerUserId())) {
                throw new BusinessException(ErrorCode.FILE_NOT_FOUND, "父级文件夹不存在");
            }
            if (parent.getPurgeState() != FilePurgeState.NONE) {
                throw new BusinessException(ErrorCode.CONFLICT, "上级文件夹正在永久删除");
            }
            ancestors.add(parent);
            parentId = parent.getParentId();
        }
        Collections.reverse(ancestors);
        for (FileNode ancestor : ancestors) {
            if (sameNameExists(ancestor.getOwnerUserId(), ancestor.getSpaceType(),
                    ancestor.getParentId(), ancestor.getName())) {
                throw new BusinessException(ErrorCode.CONFLICT, "上级文件夹同名冲突: " + ancestor.getName());
            }
        }
        return ancestors;
    }

    /**
     * 恢复后的直接父级必须存在且未删除。
     */
    void ensureParentAvailable(FileNode node) {
        if (node.getParentId() == null) {
            return;
        }
        FileNode parent = node.getSpaceType() == SpaceType.SHARED
                ? fileNodeRepository.findByIdAndSpaceTypeAndDeletedFalse(node.getParentId(), SpaceType.SHARED)
                        .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "父级文件夹不存在"))
                : fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(
                                node.getParentId(), node.getOwnerUserId())
                        .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "父级文件夹不存在"));
        if (!NodeType.FOLDER.getValue().equals(parent.getNodeType())) {
            throw new BusinessException(ErrorCode.FILE_PATH_INVALID, "父级节点不是文件夹");
        }
    }

    void markRestored(FileNode node) {
        node.setDeleted(false);
        node.setDeletedAt(null);
        node.setDeletedBy(null);
    }

    /**
     * 判断节点自身空间内的同级同名冲突。
     */
    private boolean sameNameExists(UUID ownerUserId, SpaceType spaceType, UUID parentId, String name) {
        if (spaceType == SpaceType.SHARED) {
            if (parentId == null) {
                return fileNodeRepository.existsBySpaceTypeAndParentIdIsNullAndNameAndDeletedFalse(
                        spaceType, name);
            }
            return fileNodeRepository.existsBySpaceTypeAndParentIdAndNameAndDeletedFalse(
                    spaceType, parentId, name);
        }
        if (parentId == null) {
            return fileNodeRepository.existsByOwnerUserIdAndSpaceTypeAndParentIdIsNullAndNameAndDeletedFalse(
                    ownerUserId, spaceType, name);
        }
        return fileNodeRepository.existsByOwnerUserIdAndSpaceTypeAndParentIdAndNameAndDeletedFalse(
                ownerUserId, spaceType, parentId, name);
    }
}
