package com.omninest.modules.file.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.FilePermission;
import com.omninest.modules.file.domain.FilePurgeState;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.dto.FileDescriptor;
import com.omninest.modules.file.repository.FileNodeRepository;
import java.util.Collection;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 统一校验文件生命周期状态和读取权限。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class FileLifecycleGuard {
    private final FileNodeRepository fileNodeRepository;
    private final FilePermissionService filePermissionService;
    private final SharedSpaceService sharedSpaceService;
    private final FileDownloadService fileDownloadService;

    /**
     * 校验当前用户可以读取活动文件。
     *
     * @param userId 当前用户 ID
     * @param fileNodeId 文件节点 ID
     * @return 文件描述符
     */
    @Transactional(readOnly = true)
    public FileDescriptor requireReadable(UUID userId, UUID fileNodeId) {
        FileNode node = requireActiveNode(fileNodeId);
        if (!node.getOwnerUserId().equals(userId)) {
            requireReadableByNonOwner(userId, node);
        }
        return toDescriptor(node);
    }

    /**
     * 校验当前用户可以下载活动文件。
     *
     * <p>预览只需要浏览权限，原始文件下载还必须满足共享空间 {@code CAN_DOWNLOAD}
     * 或定向分享接收关系。直接流式输出原文件的接口必须走本方法，不能只调用
     * {@link #requireReadable}。</p>
     *
     * @param userId 当前用户 ID
     * @param fileNodeId 文件节点 ID
     * @return 文件描述符
     */
    @Transactional(readOnly = true)
    public FileDescriptor requireDownloadable(UUID userId, UUID fileNodeId) {
        FileNode node = fileDownloadService.requireDownloadableNode(userId, fileNodeId);
        requireIdle(node);
        return toDescriptor(node);
    }

    /**
     * 非所有者读取节点的两种合法来源：共享空间成员，或节点被显式共享并授予查看权限。
     *
     * <p>共享空间按成员角色矩阵授权，判据与目录浏览同为 {@code CAN_BROWSE}：能列出
     * 文件名的节点必须能读出内容，否则缩略图与媒体详情都会空白。历史"文件共享"
     * 开关（{@code shared} 标志 + 逐用户 FilePermission）走另一条判定，两者互不影响。</p>
     *
     * <p>此前这里只认后者，导致共享空间里别人上传的文件"能看见却打不开"：
     * 音乐收藏与播放、影视详情、阅读正文都在这一步被拒。</p>
     */
    private void requireReadableByNonOwner(UUID userId, FileNode node) {
        if (node.getSpaceType() == SpaceType.SHARED) {
            // 共享空间总开关关闭后，历史成员仍可能持有 CAN_BROWSE，必须与列表同一判据
            sharedSpaceService.validateBrowsePermission(userId);
            return;
        }
        FilePermission permission = filePermissionService.resolvePermission(node.getId(), userId);
        if (!node.isShared() || !permission.allowView()) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "无权查看文件");
        }
    }

    /**
     * 校验当前用户拥有并可修改活动文件。
     *
     * @param ownerUserId 所有者用户 ID
     * @param fileNodeId 文件节点 ID
     * @return 文件描述符
     */
    @Transactional(readOnly = true)
    public FileDescriptor requireOwnedWritable(UUID ownerUserId, UUID fileNodeId) {
        FileNode node = fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(fileNodeId, ownerUserId)
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件不存在"));
        requireIdle(node);
        return toDescriptor(node);
    }

    /**
     * 判断当前用户拥有的文件是否仍允许异步任务处理。
     *
     * @param ownerUserId 所有者用户 ID
     * @param fileNodeId 文件节点 ID
     * @return 文件存在、未删除且未进入永久删除流程时返回 true
     */
    @Transactional(readOnly = true)
    public boolean isOwnedProcessable(UUID ownerUserId, UUID fileNodeId) {
        return fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(fileNodeId, ownerUserId)
                .map(this::isIdle)
                .orElse(false);
    }

    /**
     * 批量判定文件是否仍允许异步任务处理，供索引批处理避免逐张查询。
     *
     * @param ownerUserId 所有者用户 ID
     * @param fileNodeIds 文件节点 ID 集合
     * @return 仍可处理的文件节点 ID
     */
    @Transactional(readOnly = true)
    public Set<UUID> filterOwnedProcessable(UUID ownerUserId, Collection<UUID> fileNodeIds) {
        if (fileNodeIds == null || fileNodeIds.isEmpty()) {
            return Set.of();
        }
        return fileNodeRepository.findByOwnerUserIdAndIdInAndDeletedFalse(ownerUserId, fileNodeIds)
                .stream()
                .filter(this::isIdle)
                .map(FileNode::getId)
                .collect(Collectors.toSet());
    }

    /**
     * 取得仍允许异步任务处理的文件描述符。
     *
     * <p>与 {@link #isOwnedProcessable} 同一判据，但把节点带出来：写搜索索引时要按文件的
     * 真实空间落 {@code spaceType}，共享空间的文档如果被硬编码成个人空间，删除旧文档后
     * 会在共享检索里消失、在上传者个人检索里越权命中。
     *
     * @param ownerUserId 所有者用户 ID
     * @param fileNodeId 文件节点 ID
     * @return 文件存在、未删除且未进入永久删除流程时返回描述符，否则空
     */
    @Transactional(readOnly = true)
    public Optional<FileDescriptor> findOwnedProcessable(UUID ownerUserId, UUID fileNodeId) {
        return fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(fileNodeId, ownerUserId)
                .filter(this::isIdle)
                .map(this::toDescriptor);
    }

    /**
     * 校验回收站文件仍允许恢复。
     *
     * @param ownerUserId 所有者用户 ID
     * @param fileNodeId 文件节点 ID
     */
    @Transactional(readOnly = true)
    public void requireRestorable(UUID ownerUserId, UUID fileNodeId) {
        FileNode node = fileNodeRepository.findByIdAndOwnerUserId(fileNodeId, ownerUserId)
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件不存在"));
        if (!node.isDeleted()) {
            throw new BusinessException(ErrorCode.CONFLICT, "文件不在回收站中");
        }
        requireIdle(node);
    }

    private FileNode requireActiveNode(UUID fileNodeId) {
        FileNode node = fileNodeRepository.findByIdAndDeletedFalse(fileNodeId)
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件不存在"));
        requireIdle(node);
        return node;
    }

    private void requireIdle(FileNode node) {
        if (!isIdle(node)) {
            throw new BusinessException(ErrorCode.FILE_LIFECYCLE_CONFLICT, "文件正在执行永久删除任务");
        }
    }

    private boolean isIdle(FileNode node) {
        FilePurgeState state = node.getPurgeState();
        return state == null || state == FilePurgeState.NONE;
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
}
