package com.omninest.modules.file.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.util.LikePatterns;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.FilePurgeState;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.dto.MediaImportTaskDto;
import com.omninest.modules.file.dto.RequestMediaImportDto;
import com.omninest.modules.file.event.FileUploadedEvent;
import com.omninest.modules.file.repository.FileNodeRepository;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 将文件库中已上传的媒体重新投递至媒体识别流程。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class FileMediaImportRequestService {
    private static final Set<String> VIDEO_EXTENSIONS = Set.of(
            "mp4", "mkv", "webm", "mov", "m4v", "avi", "flv", "wmv", "ts", "m2ts",
            "mpg", "mpeg", "rmvb"
    );
    private static final Set<String> PHOTO_EXTENSIONS = Set.of(
            "jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "avif", "bmp",
            "tif", "tiff", "cr2", "cr3", "nef", "arw", "raf", "orf", "rw2", "dng"
    );
    private static final Set<String> MUSIC_EXTENSIONS = Set.of(
            "mp3", "flac", "aac", "m4a", "ogg", "opus", "wav", "wma",
            "ape", "aiff", "aif", "alac"
    );
    private static final int MAX_EXPANDED_FILE_COUNT = 500;

    private final FileNodeRepository fileNodeRepository;
    private final FileLifecycleGuard fileLifecycleGuard;
    private final FilePostProcessingTaskService postProcessingTaskService;

    /**
     * 校验所选文件/目录（支持个人空间与具读权限的共享空间）并展开目录中的匹配媒体，
     * 批量场景下对单个不兼容或不可用文件执行容错跳过，避免中断整批导入。
     *
     * @param ownerUserId 当前用户 ID
     * @param request 请求参数
     * @return 已排入媒体识别队列的文件与任务 ID
     */
    @Transactional(rollbackFor = Exception.class)
    public List<MediaImportTaskDto> request(UUID ownerUserId, RequestMediaImportDto request) {
        List<UUID> ids = List.copyOf(new LinkedHashSet<>(request.fileNodeIds()));
        if (ids.size() != request.fileNodeIds().size()) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "文件列表不能包含重复项");
        }
        boolean batchMode = ids.size() > 1;
        Map<UUID, FileNode> nodesById = new HashMap<>();
        for (FileNode node : fileNodeRepository.findAllById(ids)) {
            if (!node.isDeleted()) {
                nodesById.put(node.getId(), node);
            }
        }
        if (!batchMode && nodesById.size() != ids.size()) {
            throw new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件不存在");
        }

        Map<UUID, FileNode> importNodes = new LinkedHashMap<>();
        List<String> skippedReasons = new ArrayList<>();
        for (UUID id : ids) {
            FileNode node = nodesById.get(id);
            if (node == null) {
                skippedReasons.add(id + ":文件不存在");
                continue;
            }
            try {
                validateAccess(ownerUserId, node);
            } catch (BusinessException accessException) {
                if (!batchMode) {
                    throw accessException;
                }
                log.warn("批量媒体导入跳过无权限或不可用节点: fileNodeId={}, reason={}",
                        id, accessException.getMessage());
                skippedReasons.add(node.getName() + ":" + accessException.getMessage());
                continue;
            }

            if ("FILE".equals(node.getNodeType())) {
                if (!isImportable(node, request.mediaType())) {
                    if (!batchMode) {
                        throw new BusinessException(
                                ErrorCode.MEDIA_FORMAT_UNSUPPORTED, "所选文件与目标媒体类型不匹配");
                    }
                    log.info("批量媒体导入跳过不兼容文件: fileNodeId={}, name={}, mediaType={}",
                            id, node.getName(), request.mediaType());
                    skippedReasons.add(node.getName() + ":格式不匹配");
                    continue;
                }
                importNodes.put(node.getId(), node);
            } else if ("FOLDER".equals(node.getNodeType())) {
                expandFolder(ownerUserId, node, request.mediaType(), importNodes);
            } else {
                if (!batchMode) {
                    throw new BusinessException(ErrorCode.PARAM_ERROR, "节点类型不支持媒体导入");
                }
                skippedReasons.add(node.getName() + ":节点类型不支持");
            }
        }

        if (importNodes.isEmpty()) {
            throw new BusinessException(ErrorCode.MEDIA_FORMAT_UNSUPPORTED, "所选文件或目录中没有兼容的媒体文件");
        }
        if (importNodes.size() > MAX_EXPANDED_FILE_COUNT) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "单次最多导入 500 个媒体文件");
        }

        Set<UUID> personalIds = new LinkedHashSet<>();
        for (FileNode node : importNodes.values()) {
            if (node.getSpaceType() == SpaceType.PERSONAL && ownerUserId.equals(node.getOwnerUserId())) {
                personalIds.add(node.getId());
            }
        }
        Set<UUID> processablePersonalIds = personalIds.isEmpty()
                ? Set.of()
                : fileLifecycleGuard.filterOwnedProcessable(ownerUserId, personalIds);
        importNodes.entrySet().removeIf(entry -> {
            FileNode node = entry.getValue();
            if (node.getSpaceType() == SpaceType.PERSONAL && ownerUserId.equals(node.getOwnerUserId())) {
                return !processablePersonalIds.contains(node.getId());
            }
            FilePurgeState state = node.getPurgeState();
            return state != null && state != FilePurgeState.NONE;
        });
        if (importNodes.isEmpty()) {
            throw new BusinessException(ErrorCode.CONFLICT, "所选媒体文件正在删除或不可用");
        }

        List<MediaImportTaskDto> tasks = new ArrayList<>(importNodes.size());
        for (FileNode node : importNodes.values()) {
            try {
                UUID taskId = postProcessingTaskService.enqueueMediaAutoImport(
                        FileUploadedEvent.fromNode(node)
                );
                tasks.add(new MediaImportTaskDto(node.getId(), taskId));
            } catch (RuntimeException exception) {
                if (!batchMode && importNodes.size() == 1) {
                    throw exception;
                }
                log.warn("批量媒体导入单文件入队失败已跳过: fileNodeId={}, name={}, error={}",
                        node.getId(), node.getName(), exception.getMessage());
                skippedReasons.add(node.getName() + ":入队失败");
            }
        }
        if (tasks.isEmpty()) {
            throw new BusinessException(ErrorCode.CONFLICT, "媒体导入任务创建失败，请稍后重试");
        }
        if (!skippedReasons.isEmpty()) {
            log.info("批量媒体导入完成: userId={}, queued={}, skipped={}",
                    ownerUserId, tasks.size(), skippedReasons.size());
        }
        return tasks;
    }

    private void validateAccess(UUID requesterUserId, FileNode node) {
        if (node.getSpaceType() == SpaceType.SHARED) {
            fileLifecycleGuard.requireReadable(requesterUserId, node.getId());
            return;
        }
        if (node.getSpaceType() == SpaceType.PERSONAL) {
            fileLifecycleGuard.requireOwnedWritable(requesterUserId, node.getId());
            return;
        }
        throw new BusinessException(ErrorCode.FORBIDDEN, "当前空间不支持导入媒体");
    }

    private void expandFolder(
            UUID requesterUserId,
            FileNode folder,
            String mediaType,
            Map<UUID, FileNode> importNodes
    ) {
        String prefix = LikePatterns.escapeSpecials(folder.getNormalizedPath() + "/");
        List<FileNode> descendants = folder.getSpaceType() == SpaceType.SHARED
                ? fileNodeRepository.findBySpaceTypeAndNormalizedPathStartingWithAndDeletedFalse(
                        SpaceType.SHARED, prefix)
                : fileNodeRepository.findByOwnerUserIdAndSpaceTypeAndNormalizedPathStartingWithAndDeletedFalse(
                        requesterUserId, SpaceType.PERSONAL, prefix);
        for (FileNode descendant : descendants) {
            if ("FILE".equals(descendant.getNodeType()) && isImportable(descendant, mediaType)) {
                importNodes.putIfAbsent(descendant.getId(), descendant);
                if (importNodes.size() > MAX_EXPANDED_FILE_COUNT) {
                    throw new BusinessException(ErrorCode.PARAM_ERROR, "单次最多导入 500 个媒体文件");
                }
            }
        }
    }

    private boolean isImportable(FileNode node, String mediaType) {
        return "FILE".equals(node.getNodeType())
                && !"DERIVED".equals(node.getSourceType())
                && !"LOCAL_FILESYSTEM".equals(node.getSourceType())
                && supports(mediaType, node.getName(), node.getMimeType());
    }

    private boolean supports(String mediaType, String name, String mimeType) {
        String mime = mimeType == null ? "" : mimeType.toLowerCase(Locale.ROOT);
        String fileName = name == null ? "" : name;
        int dot = fileName.lastIndexOf('.');
        String extension = dot < 0 ? "" : fileName.substring(dot + 1).toLowerCase(Locale.ROOT);
        return switch (mediaType) {
            case "VIDEO" -> mime.startsWith("video/") || VIDEO_EXTENSIONS.contains(extension);
            case "PHOTO" -> mime.startsWith("image/")
                    || PHOTO_EXTENSIONS.contains(extension)
                    || VIDEO_EXTENSIONS.contains(extension);
            case "MUSIC" -> mime.startsWith("audio/") || MUSIC_EXTENSIONS.contains(extension);
            default -> false;
        };
    }
}
