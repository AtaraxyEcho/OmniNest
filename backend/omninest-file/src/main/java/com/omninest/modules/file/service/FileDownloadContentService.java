package com.omninest.modules.file.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.NodeType;
import com.omninest.modules.file.domain.SpaceType;
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
    public FileDownloadUrlDto createDownloadUrl(UUID ownerUserId, UUID fileId) {
        return fileDownloadService.createDownloadUrl(ownerUserId, fileId);
    }

    @Transactional(readOnly = true)
    public Map<UUID, FileDownloadUrlDto> createDownloadUrls(UUID ownerUserId, Collection<UUID> fileIds) {
        return fileDownloadService.createDownloadUrls(ownerUserId, fileIds);
    }

    @Transactional(readOnly = true)
    public FileDownloadUrlDto createReadableDownloadUrl(UUID userId, UUID fileId) {
        FileNode node = findReadableFileNode(userId, fileId);
        if (!NodeType.FILE.getValue().equals(node.getNodeType())) {
            throw new BusinessException(ErrorCode.FILE_PATH_INVALID, "文件夹不能直接下载");
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
    public FileDownloadUrlDto createDownloadUrlForShared(UUID userId, UUID fileId) {
        return fileDownloadService.createDownloadUrlForShared(userId, fileId);
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
