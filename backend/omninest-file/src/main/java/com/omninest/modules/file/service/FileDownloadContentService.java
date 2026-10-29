package com.omninest.modules.file.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.security.RequestPrincipal;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.NodeType;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.dto.FileContentRange;
import com.omninest.modules.file.dto.FileContentStream;
import com.omninest.modules.file.dto.FileDownloadUrlDto;
import com.omninest.modules.file.dto.FileMediaInfoDto;
import com.omninest.modules.file.dto.FileProcessInput;
import com.omninest.modules.file.repository.FileNodeRepository;
import java.util.Collection;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 文件下载地址、内容流与媒体元数据读取。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
class FileDownloadContentService {

    private final FileNodeLookupSupport lookup;
    private final FileNodeRepository fileNodeRepository;
    private final FileContentAccessService fileContentAccessService;
    private final SharedSpaceService sharedSpaceService;
    private final FileShareRecipientAccessService shareRecipientAccessService;
    private final FileDownloadService fileDownloadService;
    private final MediaProbeService mediaProbeService;
    private final MediaProbeSourceStager mediaProbeSourceStager;

    @Transactional(readOnly = true)
    public FileDownloadUrlDto createDownloadUrl(RequestPrincipal requester, UUID fileId) {
        return fileDownloadService.createDownloadUrl(requester, fileId);
    }

    @Transactional(readOnly = true)
    public Map<UUID, FileDownloadUrlDto> createDownloadUrls(
            RequestPrincipal requester, Collection<UUID> fileIds) {
        return fileDownloadService.createDownloadUrls(requester, fileIds);
    }

    @Transactional(readOnly = true)
    public FileDownloadUrlDto createDownloadUrlAs(UUID actorUserId, UUID fileId) {
        return fileDownloadService.createDownloadUrlAs(actorUserId, fileId);
    }

    @Transactional(readOnly = true)
    public Map<UUID, FileDownloadUrlDto> createDownloadUrlsAs(
            UUID actorUserId, Collection<UUID> fileIds) {
        return fileDownloadService.createDownloadUrlsAs(actorUserId, fileIds);
    }

    @Transactional(readOnly = true)
    public FileDownloadUrlDto createReadableDownloadUrl(RequestPrincipal requester, UUID fileId) {
        UUID userId = requester.userId();
        FileNode node = findReadableFileNode(userId, fileId);
        if (!NodeType.FILE.getValue().equals(node.getNodeType())) {
            throw new BusinessException(ErrorCode.FILE_PATH_INVALID, "文件夹不能直接下载");
        }
        // 受控在线预览（openReadableFileContent）只需要浏览权限；签发原始文件下载地址
        // 还必须具备共享空间的 CAN_DOWNLOAD，否则浏览权限等于无条件下载。
        if (node.getSpaceType() == SpaceType.SHARED
                && !node.getOwnerUserId().equals(userId)
                && !sharedSpaceService.canDownload(userId)) {
            throw new BusinessException(ErrorCode.DOWNLOAD_PERMISSION_REQUIRED, "无权下载该文件");
        }
        return fileContentAccessService.createDownloadUrl(node);
    }

    @Transactional(readOnly = true)
    public FileProcessInput createOwnedProcessInput(UUID ownerUserId, UUID fileId) {
        FileNode node = lookup.findActiveNode(ownerUserId, fileId);
        if (!NodeType.FILE.getValue().equals(node.getNodeType())) {
            throw new BusinessException(ErrorCode.FILE_PATH_INVALID, "文件节点没有可读取内容");
        }
        return fileContentAccessService.createProcessInput(node);
    }

    public FileProcessInput createOwnedContainerProcessInput(UUID ownerUserId, UUID fileId) {
        FileNode node = lookup.findActiveNode(ownerUserId, fileId);
        if (!NodeType.FILE.getValue().equals(node.getNodeType())) {
            throw new BusinessException(ErrorCode.FILE_PATH_INVALID, "文件节点没有可读取内容");
        }
        return fileContentAccessService.createContainerProcessInput(node);
    }

    @Transactional(readOnly = true)
    public FileContentStream openOwnedFileContent(UUID ownerUserId, UUID fileId) {
        FileNode node = lookup.findActiveNode(ownerUserId, fileId);
        if (!NodeType.FILE.getValue().equals(node.getNodeType())) {
            throw new BusinessException(ErrorCode.FILE_PATH_INVALID, "文件节点没有可读取内容");
        }
        return fileContentAccessService.open(node);
    }

    @Transactional(readOnly = true)
    public FileContentStream openReadableFileContent(UUID userId, UUID fileId) {
        FileNode node = findReadableFileNode(userId, fileId);
        if (!NodeType.FILE.getValue().equals(node.getNodeType())) {
            throw new BusinessException(ErrorCode.FILE_PATH_INVALID, "文件节点没有可读取内容");
        }
        return fileContentAccessService.open(node);
    }

    @Transactional(readOnly = true)
    public void requireDownloadable(RequestPrincipal requester, UUID fileId) {
        fileDownloadService.requireDownloadableNode(requester, fileId);
    }

    @Transactional(readOnly = true)
    public FileContentStream openDownloadableFileContent(RequestPrincipal requester, UUID fileId) {
        FileNode node = fileDownloadService.requireDownloadableNode(requester, fileId);
        return fileContentAccessService.open(node);
    }

    @Transactional(readOnly = true)
    public Optional<FileContentRange> openDownloadableFileRange(
            RequestPrincipal requester, UUID fileId, long offset, long length) {
        FileNode node = fileDownloadService.requireDownloadableNode(requester, fileId);
        return fileContentAccessService.openRange(node, offset, length);
    }

    @Transactional(readOnly = true)
    public void validateOwnedImage(UUID ownerUserId, UUID fileId) {
        FileNode node = lookup.findActiveNode(ownerUserId, fileId);
        String mimeType = node.getMimeType();
        if (!NodeType.FILE.getValue().equals(node.getNodeType())
                || mimeType == null
                || !mimeType.toLowerCase(Locale.ROOT).startsWith("image/")) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "封面文件必须是有效图片");
        }
    }

    @Transactional(readOnly = true)
    public FileDownloadUrlDto createDownloadUrlForShared(RequestPrincipal requester, UUID fileId) {
        return fileDownloadService.createDownloadUrlForShared(requester, fileId);
    }

    public FileMediaInfoDto mediaInfo(UUID ownerUserId, UUID fileId) {
        FileNode node = lookup.findActiveNode(ownerUserId, fileId);
        if (!NodeType.FILE.getValue().equals(node.getNodeType())) {
            throw new BusinessException(ErrorCode.FILE_PATH_INVALID, "文件夹没有媒体元数据");
        }
        String mime = node.getMimeType() == null ? "" : node.getMimeType();
        if (!mime.startsWith("video/") && !mime.startsWith("image/")) {
            return new FileMediaInfoDto(null, null, null);
        }
        if (node.getCurrentObjectId() == null) {
            return new FileMediaInfoDto(null, null, null);
        }
        return probeMediaInfo(node);
    }

    private FileNode findReadableFileNode(UUID userId, UUID fileId) {
        FileNode node = fileNodeRepository.findByIdAndDeletedFalse(fileId)
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件不存在"));
        if (node.getOwnerUserId().equals(userId)) {
            return node;
        }
        if (node.getSpaceType() == SpaceType.SHARED) {
            if (!sharedSpaceService.canBrowse(userId)
                    && !shareRecipientAccessService.canAccessRecipientNode(userId, node)) {
                throw new BusinessException(ErrorCode.FORBIDDEN, "无权查看文件");
            }
            return node;
        }
        if (!shareRecipientAccessService.canAccessRecipientNode(userId, node)) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "无权查看文件");
        }
        return node;
    }

    private FileMediaInfoDto probeMediaInfo(FileNode node) {
        FileMediaInfoDto empty = new FileMediaInfoDto(null, null, null);
        Optional<MediaProbeSourceStager.StagedSource> staged = mediaProbeSourceStager.stage(node);
        if (staged.isEmpty()) {
            return empty;
        }
        FileMediaInfoDto first;
        boolean escalate;
        try (MediaProbeSourceStager.StagedSource source = staged.get()) {
            first = mediaProbeService.probe(
                    probeCacheKey(node, MediaProbeSourceStager.DEFAULT_TAIL_BYTES), source.path());
            escalate = first.isEmpty() && source.widerTailCouldHelp();
        }
        if (!escalate) {
            return first;
        }
        Optional<MediaProbeSourceStager.StagedSource> wide = mediaProbeSourceStager
                .stage(node, MediaProbeSourceStager.ESCALATED_TAIL_BYTES);
        if (wide.isEmpty()) {
            return first;
        }
        try (MediaProbeSourceStager.StagedSource source = wide.get()) {
            return mediaProbeService.probe(
                    probeCacheKey(node, MediaProbeSourceStager.ESCALATED_TAIL_BYTES), source.path());
        }
    }

    private static String probeCacheKey(FileNode node, long tailBytes) {
        return node.getCurrentObjectId() + ":tail=" + tailBytes;
    }
}
