package com.omninest.modules.file.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.FilePermission;
import com.omninest.modules.file.domain.NodeType;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.dto.FileDownloadUrlDto;
import com.omninest.modules.file.repository.FileNodeRepository;
import java.util.Collection;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 文件下载地址签发服务。
 *
 * <p>个人空间只允许所有者；共享空间成员凭 CAN_BROWSE + CAN_DOWNLOAD 读取；
 * 个人空间通过分享链接授权的文件沿用细粒度权限。从 {@link FileQueryService} 拆出，
 * 避免单文件继续膨胀并集中下载权限判定。</p>
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class FileDownloadService {

    private final FileNodeRepository fileNodeRepository;
    private final FileContentAccessService fileContentAccessService;
    private final FilePermissionService filePermissionService;
    private final SharedSpaceService sharedSpaceService;

    /**
     * 为可下载节点创建短期下载地址。
     *
     * @param userId 当前用户
     * @param fileId 文件节点 ID
     * @return 下载地址
     */
    @Transactional(readOnly = true)
    public FileDownloadUrlDto createDownloadUrl(UUID userId, UUID fileId) {
        return fileContentAccessService.createDownloadUrl(requireDownloadableNode(userId, fileId));
    }

    /**
     * 批量为当前用户可下载的文件创建短期下载地址。
     *
     * @param userId 当前用户
     * @param fileIds 文件节点 ID 集合
     * @return 文件节点 ID 到下载地址的映射
     */
    @Transactional(readOnly = true)
    public Map<UUID, FileDownloadUrlDto> createDownloadUrls(UUID userId, Collection<UUID> fileIds) {
        if (fileIds == null || fileIds.isEmpty()) {
            return Map.of();
        }
        List<FileNode> candidates = fileNodeRepository.findAllById(fileIds).stream()
                .filter(node -> !node.isDeleted()
                        && NodeType.FILE.getValue().equals(node.getNodeType()))
                .toList();
        boolean sharedDownloadAllowed = candidates.stream()
                .anyMatch(node -> node.getSpaceType() == SpaceType.SHARED
                        && !userId.equals(node.getOwnerUserId()))
                && sharedSpaceService.canDownload(userId);
        List<FileNode> nodes = candidates.stream()
                .filter(node -> userId.equals(node.getOwnerUserId())
                        || (node.getSpaceType() == SpaceType.SHARED && sharedDownloadAllowed))
                .toList();
        return fileContentAccessService.createDownloadUrls(nodes);
    }

    /**
     * 生成共享文件的下载 URL：所有者直接放行，否则校验共享空间或分享权限。
     *
     * @param userId 当前用户
     * @param fileId 文件节点 ID
     * @return 下载地址
     */
    @Transactional(readOnly = true)
    public FileDownloadUrlDto createDownloadUrlForShared(UUID userId, UUID fileId) {
        FileNode node = fileNodeRepository.findByIdAndDeletedFalse(fileId)
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件不存在"));
        if (node.getOwnerUserId().equals(userId)) {
            return createDownloadUrl(userId, fileId);
        }
        if (node.getSpaceType() == SpaceType.SHARED) {
            sharedSpaceService.validateDownloadPermission(userId);
            requireFileNode(node);
            return fileContentAccessService.createDownloadUrl(node);
        }
        if (!node.isShared()) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "文件未共享");
        }
        FilePermission permission = filePermissionService.resolvePermission(fileId, userId);
        if (!permission.allowDownload()) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "无下载权限");
        }
        requireFileNode(node);
        return fileContentAccessService.createDownloadUrl(node);
    }

    private FileNode requireDownloadableNode(UUID userId, UUID fileId) {
        FileNode node = fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(fileId, userId)
                .orElseGet(() -> fileNodeRepository.findByIdAndDeletedFalse(fileId)
                        .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件不存在")));
        if (!node.getOwnerUserId().equals(userId)) {
            if (node.getSpaceType() != SpaceType.SHARED) {
                throw new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件不存在");
            }
            sharedSpaceService.validateDownloadPermission(userId);
        }
        requireFileNode(node);
        return node;
    }

    private void requireFileNode(FileNode node) {
        if (!NodeType.FILE.getValue().equals(node.getNodeType())) {
            throw new BusinessException(ErrorCode.FILE_PATH_INVALID, "文件夹不能直接下载");
        }
    }
}
