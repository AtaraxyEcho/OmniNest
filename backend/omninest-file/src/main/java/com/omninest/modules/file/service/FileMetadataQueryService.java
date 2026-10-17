package com.omninest.modules.file.service;

import com.omninest.common.util.LikePatterns;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.NodeType;
import com.omninest.modules.file.domain.FileObject;
import com.omninest.modules.file.dto.FileDescriptor;
import com.omninest.modules.file.dto.FileObjectDescriptor;
import com.omninest.modules.file.repository.FileNodeRepository;
import com.omninest.modules.file.repository.FileObjectRepository;
import java.util.Collection;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 文件元数据查询服务，向其他模块提供不包含 JPA 实体的只读结果。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class FileMetadataQueryService {

    private final FileNodeRepository fileNodeRepository;
    private final FileObjectRepository fileObjectRepository;

    /**
     * 按 ID 查询文件节点。
     *
     * @param fileId 文件节点 ID
     * @return 文件描述符，不存在时返回空
     */
    @Transactional(readOnly = true)
    public Optional<FileDescriptor> findById(UUID fileId) {
        return fileNodeRepository.findById(fileId).map(this::toDescriptor);
    }

    /**
     * 按 ID 查询未删除文件节点。
     *
     * @param fileId 文件节点 ID
     * @return 文件描述符，不存在时返回空
     */
    @Transactional(readOnly = true)
    public Optional<FileDescriptor> findActiveById(UUID fileId) {
        return fileNodeRepository.findByIdAndDeletedFalse(fileId).map(this::toDescriptor);
    }

    /**
     * 查询用户拥有的未删除文件节点。
     *
     * @param ownerUserId 所有者用户 ID
     * @param fileId 文件节点 ID
     * @return 文件描述符，不存在时返回空
     */
    @Transactional(readOnly = true)
    public Optional<FileDescriptor> findOwnedActive(UUID ownerUserId, UUID fileId) {
        return fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(fileId, ownerUserId)
                .map(this::toDescriptor);
    }

    /**
     * 批量查询文件节点。
     *
     * @param fileIds 文件节点 ID 集合
     * @return 文件描述符列表
     */
    @Transactional(readOnly = true)
    public List<FileDescriptor> findAllByIds(Collection<UUID> fileIds) {
        return fileNodeRepository.findAllById(fileIds).stream().map(this::toDescriptor).toList();
    }

    /**
     * 查询用户拥有的全部未删除文件节点。
     *
     * @param ownerUserId 所有者用户 ID
     * @return 文件描述符列表
     */
    @Transactional(readOnly = true)
    public List<FileDescriptor> listOwnedActive(UUID ownerUserId) {
        return fileNodeRepository.findByOwnerUserIdAndDeletedFalse(ownerUserId)
                .stream().map(this::toDescriptor).toList();
    }

    /**
     * 查询用户拥有的未删除文件（不含目录），供只需要文件的批量候选场景使用。
     *
     * @param ownerUserId 所有者用户 ID
     * @return 文件描述符列表
     */
    @Transactional(readOnly = true)
    public List<FileDescriptor> listOwnedActiveFiles(UUID ownerUserId) {
        return fileNodeRepository.findByOwnerUserIdAndNodeTypeAndDeletedFalse(
                        ownerUserId, NodeType.FILE.getValue())
                .stream().map(this::toDescriptor).toList();
    }

    /**
     * 查询用户指定父目录下拥有的未删除文件节点。
     *
     * @param ownerUserId 所有者用户 ID
     * @param parentId 父目录 ID
     * @return 文件描述符列表
     */
    @Transactional(readOnly = true)
    public List<FileDescriptor> listOwnedActiveChildren(UUID ownerUserId, UUID parentId) {
        return fileNodeRepository.findByOwnerUserIdAndParentIdAndDeletedFalse(ownerUserId, parentId)
                .stream().map(this::toDescriptor).toList();
    }

    /**
     * 查询标记为共享且不属于当前用户的未删除文件候选。
     *
     * @param userId 当前用户 ID
     * @return 共享文件描述符列表
     */
    @Transactional(readOnly = true)
    public List<FileDescriptor> listSharedVisibleToUser(UUID userId) {
        return fileNodeRepository.findSharedFilesVisibleToUser(userId)
                .stream().map(this::toDescriptor).toList();
    }

    /**
     * 查询指定空间内的全部未删除文件（不含目录）。
     *
     * @param spaceType 空间类型
     * @return 文件描述符列表
     */
    @Transactional(readOnly = true)
    public List<FileDescriptor> listActiveFilesBySpace(SpaceType spaceType) {
        return fileNodeRepository.findBySpaceTypeAndNodeTypeAndDeletedFalse(
                        spaceType, NodeType.FILE.getValue())
                .stream().map(this::toDescriptor).toList();
    }

    /**
     * 查询用户指定空间与路径前缀下的未删除文件节点。
     *
     * <p>空间维度不可省略：个人与共享可以存在同名目录，只按 owner + 前缀会把另一空间的
     * 子树一起交给调用方（影视扫描会据此登记业务引用）。</p>
     *
     * @param ownerUserId 所有者用户 ID
     * @param spaceType 空间类型
     * @param prefix 路径前缀
     * @return 文件描述符列表
     */
    @Transactional(readOnly = true)
    public List<FileDescriptor> listOwnedActiveByPathPrefix(
            UUID ownerUserId, SpaceType spaceType, String prefix) {
        // 入参是字面量路径前缀（跨模块调用方不预先转义），转义只发生在这里一次。
        return fileNodeRepository.findByOwnerUserIdAndSpaceTypeAndNormalizedPathStartingWithAndDeletedFalse(
                ownerUserId, spaceType, LikePatterns.escapeSpecials(prefix))
                .stream().map(this::toDescriptor).toList();
    }

    /**
     * 查询用户拥有的图片文件。
     *
     * @param ownerUserId 所有者用户 ID
     * @return 图片文件描述符列表
     */
    @Transactional(readOnly = true)
    public List<FileDescriptor> listOwnedImages(UUID ownerUserId) {
        return fileNodeRepository.findImageFilesByOwnerUserId(ownerUserId)
                .stream().map(this::toDescriptor).toList();
    }

    /**
     * 查询用户可见的共享图片文件候选。
     *
     * @param userId 当前用户 ID
     * @return 共享图片文件描述符列表
     */
    @Transactional(readOnly = true)
    public List<FileDescriptor> listSharedImagesVisibleToUser(UUID userId) {
        return fileNodeRepository.findSharedImageFilesVisibleToUser(userId)
                .stream().map(this::toDescriptor).toList();
    }

    /**
     * 查询用户指定的未删除路径。
     *
     * @param ownerUserId 所有者用户 ID
     * @param normalizedPath 规范化路径
     * @return 文件描述符，不存在时返回空
     */
    @Transactional(readOnly = true)
    public Optional<FileDescriptor> findActivePath(UUID ownerUserId, String normalizedPath) {
        return fileNodeRepository.findActivePath(ownerUserId, normalizedPath).map(this::toDescriptor);
    }

    /**
     * 查询文件节点当前内容的 SHA-256，不向业务模块暴露对象存储位置。
     *
     * @param fileNodeId 文件节点 ID
     * @return 内容摘要；非对象存储来源或摘要缺失时返回空
     */
    @Transactional(readOnly = true)
    public Optional<String> findContentSha256(UUID fileNodeId) {
        return fileNodeRepository.findById(fileNodeId)
                .map(FileNode::getCurrentObjectId)
                .flatMap(fileObjectRepository::findById)
                .map(FileObject::getSha256)
                .filter(value -> !value.isBlank());
    }

    /**
     * 批量查询文件节点当前内容的 SHA-256。
     *
     * @param fileNodeIds 文件节点 ID 集合
     * @return 以文件节点 ID 为键的内容摘要，只包含摘要有效的节点
     */
    @Transactional(readOnly = true)
    public Map<UUID, String> findContentSha256ByFileNodeIds(Collection<UUID> fileNodeIds) {
        if (fileNodeIds == null || fileNodeIds.isEmpty()) {
            return Map.of();
        }
        List<FileNode> nodes = fileNodeRepository.findAllById(fileNodeIds);
        List<UUID> objectIds = nodes.stream()
                .map(FileNode::getCurrentObjectId)
                .filter(id -> id != null)
                .distinct()
                .toList();
        if (objectIds.isEmpty()) {
            return Map.of();
        }
        Map<UUID, String> hashesByObjectId = new HashMap<>();
        for (FileObject object : fileObjectRepository.findAllById(objectIds)) {
            if (object.getSha256() != null && !object.getSha256().isBlank()) {
                hashesByObjectId.put(object.getId(), object.getSha256());
            }
        }
        Map<UUID, String> result = new HashMap<>();
        for (FileNode node : nodes) {
            String sha256 = hashesByObjectId.get(node.getCurrentObjectId());
            if (sha256 != null) {
                result.put(node.getId(), sha256);
            }
        }
        return Map.copyOf(result);
    }

    /**
     * 按 ID 查询文件对象。
     *
     * @param objectId 文件对象 ID
     * @return 文件对象描述符，不存在时返回空
     */
    @Transactional(readOnly = true)
    public Optional<FileObjectDescriptor> findObjectById(UUID objectId) {
        return fileObjectRepository.findById(objectId).map(this::toObjectDescriptor);
    }

    /**
     * 批量查询文件对象，供跨模块按已持久化摘要执行轻量去重。
     *
     * @param objectIds 文件对象 ID 集合
     * @return 文件对象描述符列表
     */
    @Transactional(readOnly = true)
    public List<FileObjectDescriptor> findObjectsByIds(Collection<UUID> objectIds) {
        if (objectIds == null || objectIds.isEmpty()) {
            return List.of();
        }
        return fileObjectRepository.findAllById(objectIds).stream()
                .map(this::toObjectDescriptor)
                .toList();
    }

    private FileDescriptor toDescriptor(FileNode node) {
        return new FileDescriptor(
                node.getId(),
                node.getOwnerUserId(),
                node.getParentId(),
                node.getNodeType(),
                node.getName(),
                node.getNormalizedPath(),
                node.getMimeType(),
                node.getSizeBytes(),
                node.getCurrentObjectId(),
                node.getSourceType(),
                node.isDeleted(),
                node.isShared(),
                node.getSpaceType(),
                node.getUploadedBy(),
                node.getCreatedAt(),
                node.getUpdatedAt()
        );
    }

    private FileObjectDescriptor toObjectDescriptor(FileObject object) {
        return new FileObjectDescriptor(
                object.getId(),
                object.getBucketName(),
                object.getObjectKey(),
                object.getSha256(),
                object.getSizeBytes(),
                object.getMimeType()
        );
    }
}
