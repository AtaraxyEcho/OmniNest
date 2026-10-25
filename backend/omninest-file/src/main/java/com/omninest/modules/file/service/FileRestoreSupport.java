package com.omninest.modules.file.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.FilePurgeState;
import com.omninest.modules.file.domain.NodeType;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.repository.FileNodeRepository;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Objects;
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

    private final FileNodeRepository fileNodeRepository;
    private final FileNodeLookupSupport lookup;

    /**
     * 取子树内待恢复的软删除节点。
     */
    List<FileNode> deletedSubtreeNodes(FileNode node) {
        if (node.getSpaceType() == SpaceType.SHARED) {
            return fileNodeRepository.findDeletedBySpaceTypeAndNormalizedPathStartingWith(
                    SpaceType.SHARED, lookup.subtreePrefix(node));
        }
        return fileNodeRepository.findByOwnerUserIdAndSpaceTypeAndNormalizedPathStartingWithAndDeletedTrue(
                node.getOwnerUserId(), node.getSpaceType(), lookup.subtreePrefix(node));
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
