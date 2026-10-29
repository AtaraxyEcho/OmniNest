package com.omninest.modules.file.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.security.RequestPrincipal;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.NodeType;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.dto.FileDownloadUrlDto;
import com.omninest.modules.file.repository.FileNodeRepository;
import java.util.Collection;
import java.util.List;
import java.util.Map;
import java.util.Set;
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
    private final SharedSpaceService sharedSpaceService;
    private final FileShareRecipientAccessService shareRecipientAccessService;

    /**
     * 为可下载节点创建短期下载地址。
     *
     * @param requester 当前请求主体
     * @param fileId 文件节点 ID
     * @return 下载地址
     */
    @Transactional(readOnly = true)
    public FileDownloadUrlDto createDownloadUrl(RequestPrincipal requester, UUID fileId) {
        return fileContentAccessService.createDownloadUrl(requireDownloadableNode(requester, fileId));
    }

    /**
     * 批量为当前请求者可下载的文件创建短期下载地址。
     *
     * @param requester 当前请求主体
     * @param fileIds 文件节点 ID 集合
     * @return 文件节点 ID 到下载地址的映射
     */
    @Transactional(readOnly = true)
    public Map<UUID, FileDownloadUrlDto> createDownloadUrls(
            RequestPrincipal requester, Collection<UUID> fileIds) {
        return selectDownloadableNodes(requester.userId(), fileIds);
    }

    private Map<UUID, FileDownloadUrlDto> selectDownloadableNodes(
            UUID userId, Collection<UUID> fileIds) {
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
        boolean needsRecipientCheck = candidates.stream().anyMatch(node ->
                !userId.equals(node.getOwnerUserId())
                        && !(node.getSpaceType() == SpaceType.SHARED && sharedDownloadAllowed));
        Set<UUID> recipientAccessible = needsRecipientCheck
                ? shareRecipientAccessService.filterRecipientAccessible(userId, candidates)
                : Set.of();
        List<FileNode> nodes = candidates.stream()
                .filter(node -> userId.equals(node.getOwnerUserId())
                        || (node.getSpaceType() == SpaceType.SHARED && sharedDownloadAllowed)
                        || recipientAccessible.contains(node.getId()))
                .toList();
        return fileContentAccessService.createDownloadUrls(nodes);
    }

    /**
     * 生成共享文件的下载 URL：所有者直接放行，否则校验共享空间或定向分享接收关系。
     *
     * @param requester 当前请求主体
     * @param fileId 文件节点 ID
     * @return 下载地址
     */
    @Transactional(readOnly = true)
    public FileDownloadUrlDto createDownloadUrlForShared(RequestPrincipal requester, UUID fileId) {
        UUID userId = requester.userId();
        FileNode node = fileNodeRepository.findByIdAndDeletedFalse(fileId)
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件不存在"));
        if (node.getOwnerUserId().equals(userId)) {
            return createDownloadUrl(requester, fileId);
        }
        if (node.getSpaceType() == SpaceType.SHARED) {
            // 空间权限足够时不再多查分享接收关系；定向分享是空间外成员的显式补充授权。
            if (!sharedSpaceService.canDownload(userId)
                    && !shareRecipientAccessService.canAccessRecipientNode(userId, node)) {
                throw new BusinessException(ErrorCode.DOWNLOAD_PERMISSION_REQUIRED, "无下载权限");
            }
            requireFileNode(node);
            return fileContentAccessService.createDownloadUrl(node);
        }
        // 定向分享只落 share_links + file_share_recipients；节点 shared 标志与
        // file_node_permissions 是早期模型，不能再作为当前分享的授权依据。
        if (!shareRecipientAccessService.canAccessRecipientNode(userId, node)) {
            throw new BusinessException(ErrorCode.DOWNLOAD_PERMISSION_REQUIRED, "无下载权限");
        }
        requireFileNode(node);
        return fileContentAccessService.createDownloadUrl(node);
    }

    /**
     * 以指定用户身份签发下载地址，应用该用户自身的下载能力。
     *
     * <p>只用于调用方已完成业务授权、且必须以业务对象所有者身份签发的场景：派生资产
     * （海报、封面、字幕）随业务对象展示，以及分享链接会话。请求路径上的原始文件下载
     * 必须使用 {@link #createDownloadUrl(RequestPrincipal, UUID)}；控制器禁止调用本方法。</p>
     *
     * @param actorUserId 签发身份
     * @param fileId 文件节点 ID
     * @return 下载地址
     */
    @Transactional(readOnly = true)
    public FileDownloadUrlDto createDownloadUrlAs(UUID actorUserId, UUID fileId) {
        return fileContentAccessService.createDownloadUrl(requireDownloadableNode(actorUserId, fileId));
    }

    /**
     * 批量以指定用户身份签发下载地址，按该用户的下载能力过滤不可下载节点。
     *
     * @param actorUserId 签发身份
     * @param fileIds 文件节点 ID 集合
     * @return 文件节点 ID 到下载地址的映射
     */
    @Transactional(readOnly = true)
    public Map<UUID, FileDownloadUrlDto> createDownloadUrlsAs(
            UUID actorUserId, Collection<UUID> fileIds) {
        return selectDownloadableNodes(actorUserId, fileIds);
    }

    /**
     * 校验当前请求者具备下载权限并返回可下载节点。
     *
     * <p>与只读预览不同，这里要求共享空间成员具备 {@code CAN_DOWNLOAD}，
     * 个人空间文件必须存在定向分享接收关系。供需要直接流式输出原文件的
     * 业务模块复用，避免用浏览权限绕过下载权限位。</p>
     *
     * @param requester 当前请求主体
     * @param fileId 文件节点 ID
     * @return 可下载节点
     */
    public FileNode requireDownloadableNode(RequestPrincipal requester, UUID fileId) {
        return requireDownloadableNode(requester.userId(), fileId);
    }

    private FileNode requireDownloadableNode(UUID userId, UUID fileId) {
        FileNode node = fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(fileId, userId)
                .orElseGet(() -> fileNodeRepository.findByIdAndDeletedFalse(fileId)
                        .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件不存在")));
        if (!node.getOwnerUserId().equals(userId)) {
            if (node.getSpaceType() == SpaceType.SHARED) {
                if (!sharedSpaceService.canDownload(userId)
                        && !shareRecipientAccessService.canAccessRecipientNode(userId, node)) {
                    throw new BusinessException(ErrorCode.DOWNLOAD_PERMISSION_REQUIRED, "无下载权限");
                }
            } else if (!shareRecipientAccessService.canAccessRecipientNode(userId, node)) {
                // 非所有者、非共享空间且没有定向分享关系时按不存在处理，避免存在性探测。
                throw new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件不存在");
            }
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
