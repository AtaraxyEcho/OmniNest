package com.omninest.modules.file.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.util.LikePatterns;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.dto.MediaImportTaskDto;
import com.omninest.modules.file.dto.RequestMediaImportDto;
import com.omninest.modules.file.event.FileUploadedEvent;
import com.omninest.modules.file.repository.FileNodeRepository;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 将文件库中已上传的媒体重新投递至媒体识别流程。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class FileMediaImportRequestService {
    private static final Set<String> VIDEO_EXTENSIONS = Set.of(
            "mp4", "mkv", "webm", "mov", "m4v", "avi", "flv", "wmv", "ts", "m2ts"
    );
    private static final Set<String> PHOTO_EXTENSIONS = Set.of(
            "jpg", "jpeg", "png", "gif", "heic", "heif", "bmp", "tif", "tiff",
            "cr2", "nef", "arw", "dng"
    );
    private static final Set<String> MUSIC_EXTENSIONS = Set.of(
            "mp3", "flac", "aac", "m4a", "ogg", "opus", "wav", "wma"
    );
    private static final int MAX_EXPANDED_FILE_COUNT = 500;

    private final FileNodeRepository fileNodeRepository;
    private final FileLifecycleGuard fileLifecycleGuard;
    private final FilePostProcessingTaskService postProcessingTaskService;

    /**
     * 校验所选文件/目录归当前用户所有并展开目录中的匹配媒体，原子地创建后台任务。
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
        Map<UUID, FileNode> nodesById = new HashMap<>();
        for (FileNode node : fileNodeRepository.findByOwnerUserIdAndIdInAndDeletedFalse(ownerUserId, ids)) {
            nodesById.put(node.getId(), node);
        }
        if (nodesById.size() != ids.size()) {
            throw new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件不存在");
        }

        Map<UUID, FileNode> importNodes = new LinkedHashMap<>();
        for (UUID id : ids) {
            FileNode node = nodesById.get(id);
            fileLifecycleGuard.requireOwnedWritable(ownerUserId, id);
            if (node.getSpaceType() != SpaceType.PERSONAL) {
                throw new BusinessException(ErrorCode.FORBIDDEN, "只能从个人文件中导入媒体");
            }
            if ("FILE".equals(node.getNodeType())) {
                if (!isImportable(node, request.mediaType())) {
                    throw new BusinessException(
                            ErrorCode.MEDIA_FORMAT_UNSUPPORTED, "所选文件与目标媒体类型不匹配");
                }
                importNodes.put(node.getId(), node);
            } else if ("FOLDER".equals(node.getNodeType())) {
                expandFolder(ownerUserId, node, request.mediaType(), importNodes);
            } else {
                throw new BusinessException(ErrorCode.PARAM_ERROR, "节点类型不支持媒体导入");
            }
        }

        if (importNodes.isEmpty()) {
            throw new BusinessException(ErrorCode.MEDIA_FORMAT_UNSUPPORTED, "所选目录中没有兼容的媒体文件");
        }
        if (importNodes.size() > MAX_EXPANDED_FILE_COUNT) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "单次最多导入 500 个媒体文件");
        }
        Set<UUID> processableIds = fileLifecycleGuard.filterOwnedProcessable(
                ownerUserId, importNodes.keySet());
        importNodes.keySet().retainAll(processableIds);
        if (importNodes.isEmpty()) {
            throw new BusinessException(ErrorCode.CONFLICT, "所选媒体文件正在删除或不可用");
        }

        return importNodes.values().stream()
                .map(node -> {
                    UUID taskId = postProcessingTaskService.enqueueMediaAutoImport(
                            FileUploadedEvent.fromNode(node)
                    );
                    return new MediaImportTaskDto(node.getId(), taskId);
                })
                .toList();
    }

    private void expandFolder(
            UUID ownerUserId,
            FileNode folder,
            String mediaType,
            Map<UUID, FileNode> importNodes
    ) {
        String prefix = LikePatterns.escapeSpecials(folder.getNormalizedPath() + "/");
        for (FileNode descendant : fileNodeRepository
                .findByOwnerUserIdAndSpaceTypeAndNormalizedPathStartingWithAndDeletedFalse(
                        ownerUserId, SpaceType.PERSONAL, prefix)) {
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
