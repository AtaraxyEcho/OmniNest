package com.omninest.modules.file.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.NodeType;
import com.omninest.modules.file.domain.SourceType;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.dto.FileNodeDto;
import com.omninest.modules.file.repository.FileNodeRepository;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

/**
 * 文件节点查找与 DTO 映射的共享支撑服务。
 * 供收藏、分享、版本等文件扩展服务复用，避免各服务重复实现节点可见性规则。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class FileNodeSupport {
    private final FileNodeRepository fileNodeRepository;

    /**
     * 查找用户拥有的未删除节点。
     *
     * @param ownerUserId 所有者用户 ID
     * @param fileId      文件节点 ID
     * @return 文件节点
     */
    public FileNode findActiveNode(UUID ownerUserId, UUID fileId) {
        return fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(fileId, ownerUserId)
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件不存在"));
    }

    /**
     * 查找用户可见的文件（个人空间或共享空间）。
     * 用于收藏、最近访问等需要访问共享空间文件的场景。
     *
     * @param userId 用户 ID
     * @param fileId 文件节点 ID
     * @return 文件节点
     */
    public FileNode findVisibleNode(UUID userId, UUID fileId) {
        return fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(fileId, userId)
                .orElseGet(() ->
                        fileNodeRepository.findByIdAndSpaceTypeAndDeletedFalse(fileId, SpaceType.SHARED)
                                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件不存在")));
    }

    /**
     * 查找用户拥有的未删除节点（业务对象不存在时返回 NOT_FOUND）。
     *
     * @param ownerUserId 所有者用户 ID
     * @param fileId      文件节点 ID
     * @return 文件节点
     */
    public FileNode findOwnedNode(UUID ownerUserId, UUID fileId) {
        return fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(fileId, ownerUserId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "文件不存在"));
    }

    /**
     * 校验节点允许执行分享、复制、版本等写语义操作。
     * 本地只读影视库节点拒绝此类操作。
     *
     * @param node 文件节点
     */
    public void requireShareable(FileNode node) {
        if (SourceType.LOCAL_FILESYSTEM.getValue().equals(node.getSourceType())) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "本地只读影视库文件不支持该文件操作");
        }
    }

    /**
     * 判断同级目录下是否存在同名节点。
     *
     * @param ownerUserId 所有者用户 ID
     * @param parentId    父目录 ID，null 表示根目录
     * @param name        节点名称
     * @return 是否存在同名节点
     */
    public boolean sameNameExists(UUID ownerUserId, UUID parentId, String name) {
        if (parentId == null) {
            return fileNodeRepository.existsByOwnerUserIdAndParentIdIsNullAndNameAndDeletedFalse(ownerUserId, name);
        }
        return fileNodeRepository.existsByOwnerUserIdAndParentIdAndNameAndDeletedFalse(ownerUserId, parentId, name);
    }

    /**
     * 解析子节点规范化路径。
     *
     * @param parent    父节点，null 表示根目录
     * @param childName 子节点名称
     * @return 规范化路径
     */
    public String resolveChildPath(FileNode parent, String childName) {
        if (parent == null) {
            return "/" + childName;
        }
        return parent.getNormalizedPath() + "/" + childName;
    }

    /**
     * 将文件节点映射为对外 DTO。
     *
     * @param node 文件节点
     * @return 文件节点 DTO
     */
    public FileNodeDto toNodeDto(FileNode node) {
        return new FileNodeDto(
                node.getId(),
                node.getParentId(),
                node.getNodeType(),
                node.getName(),
                node.getNormalizedPath(),
                node.getMimeType(),
                node.getSizeBytes(),
                node.isShared(),
                node.getSharedAt(),
                node.getUpdatedAt(),
                node.getSpaceType() != null ? node.getSpaceType().getValue() : "PERSONAL",
                node.getUploadedBy()
        );
    }

    /**
     * 校验并获取复制目标父文件夹。
     * 允许 targetParentId 为 null（复制到根目录）。
     *
     * @param ownerUserId    所有者用户 ID
     * @param targetParentId 目标父文件夹 ID
     * @return 目标父节点，null 表示根目录
     */
    public FileNode resolveCopyTargetParent(UUID ownerUserId, UUID targetParentId) {
        if (targetParentId == null) {
            return null;
        }
        FileNode parent = fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(targetParentId, ownerUserId)
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "目标文件夹不存在"));
        if (!NodeType.FOLDER.getValue().equals(parent.getNodeType())) {
            throw new BusinessException(ErrorCode.FILE_PATH_INVALID, "目标父级必须是文件夹");
        }
        return parent;
    }
}
