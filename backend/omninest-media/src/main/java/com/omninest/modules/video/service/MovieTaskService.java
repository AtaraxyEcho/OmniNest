package com.omninest.modules.video.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.modules.media.domain.MetadataStatus;
import com.omninest.modules.file.domain.NodeType;
import com.omninest.modules.task.domain.TaskStatus;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.dto.FileDescriptor;
import com.omninest.modules.file.service.FileMetadataQueryService;
import com.omninest.modules.task.domain.TaskRecord;
import com.omninest.modules.task.service.TaskRecordService;
import com.omninest.modules.video.domain.MediaVideoItem;
import com.omninest.modules.video.dto.MovieDtos.MovieScanRequest;
import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.video.dto.MovieDtos.MovieTaskDto;
import com.omninest.modules.video.dto.MovieDtos.ScrapeTaskDto;
import com.omninest.modules.video.event.MediaLibraryScanRequestedEvent;
import com.omninest.modules.video.event.TranscodeRequestedEvent;
import com.omninest.modules.video.repository.MediaVideoItemRepository;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 影视扫描、刮削和转码任务编排服务。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class MovieTaskService {
    private static final String MEDIA_SCAN = "MEDIA_SCAN";
    private static final String VIDEO_TRANSCODE = "VIDEO_TRANSCODE";
    private static final String WEB_OPTIMIZE = "WEB_OPTIMIZE";
    private static final int DEFAULT_TASK_LIMIT = 100;

    /**
     * 影视模块任务类型白名单：进度列表只展示本模块任务，避免串入文件/相册等其它任务。
     */
    static final Set<String> VIDEO_TASK_TYPES = Set.of(
            VIDEO_TRANSCODE,
            "AUDIO_EXTRACT",
            WEB_OPTIMIZE,
            MEDIA_SCAN,
            "MEDIA_SCRAPE",
            "LOCAL_VIDEO_LIBRARY_DISCOVERY",
            "LOCAL_VIDEO_LIBRARY_APPLY"
    );

    private final TaskRecordService taskRecordService;
    private final MediaVideoItemRepository videoItemRepository;
    private final MediaContentAccessService mediaContentAccessService;
    private final FileMetadataQueryService fileMetadataQueryService;
    private final SimpleFileNameParser fileNameParser;
    private final MovieScrapeService scrapeService;
    private final TaskDispatchService taskDispatchService;
    private final MediaRuntimeConfigService mediaRuntimeConfigService;

    @Transactional(readOnly = true)
    public List<MovieTaskDto> list(UUID ownerUserId, String taskType) {
        String normalized = normalizeTaskType(taskType);
        if (normalized == null) {
            return toTaskDtos(taskRecordService.listTasksByTypes(ownerUserId, VIDEO_TASK_TYPES, DEFAULT_TASK_LIMIT));
        }
        if (!VIDEO_TASK_TYPES.contains(normalized)) {
            return List.of();
        }
        return toTaskDtos(taskRecordService.listTasks(ownerUserId, normalized, DEFAULT_TASK_LIMIT));
    }

    private List<MovieTaskDto> toTaskDtos(List<TaskRecord> records) {
        return records.stream().map(record -> new MovieTaskDto(
                record.getId(),
                record.getTaskType(),
                record.getStatus(),
                record.getProgress(),
                record.getRoutingKey(),
                record.getErrorMessage(),
                record.getUpdatedAt()
        )).toList();
    }

    @Transactional(rollbackFor = Exception.class)
    public ScrapeTaskDto createTranscodeTask(UUID requesterUserId, UUID videoItemId) {
        return createTranscodeTask(requesterUserId, videoItemId, false);
    }

    @Transactional(rollbackFor = Exception.class)
    public ScrapeTaskDto createTranscodeTask(UUID requesterUserId, UUID videoItemId, boolean audioOnly) {
        if (!mediaRuntimeConfigService.transcodeEnabled()) {
            throw new BusinessException(ErrorCode.CONFLICT, "媒体转码未启用，请在配置中心开启 media.transcode.enabled");
        }
        MediaVideoItem videoItem = mediaContentAccessService.requireReadableVideo(requesterUserId, videoItemId);
        UUID catalogOwnerUserId = videoItem.getOwnerUserId();
        String taskType = audioOnly ? "AUDIO_EXTRACT" : VIDEO_TRANSCODE;
        UUID taskId = UUID.randomUUID();
        taskRecordService.createQueuedTask(taskId, requesterUserId, taskType, QueueNames.VIDEO_TRANSCODE_ROUTING_KEY,
                "QUEUED", "FILE_NODE", videoItem.getFileNodeId(),
                Map.of(
                        "videoItemId", videoItemId.toString(),
                        "ownerUserId", catalogOwnerUserId.toString(),
                        "requesterUserId", requesterUserId.toString(),
                        "audioOnly", audioOnly,
                        "webOptimize", false
                ));
        TranscodeRequestedEvent event = new TranscodeRequestedEvent(
                taskId, videoItemId, catalogOwnerUserId, audioOnly, false);
        // 任务记录与 Outbox 投递行在同一事务提交，避免"记录已建而消息丢失"的僵尸任务。
        taskDispatchService.enqueue(
                taskId,
                QueueNames.TASK_EXCHANGE,
                QueueNames.VIDEO_TRANSCODE_ROUTING_KEY,
                event
        );
        String message = audioOnly ? "音频提取任务已进入队列" : "转码任务已进入队列";
        return new ScrapeTaskDto(taskId, TaskStatus.QUEUED.getValue(), message);
    }

    /**
     * 创建 Web 优化转码任务：将视频转为 faststart MP4，支持浏览器原生 HTTP range seek。
     */
    @Transactional(rollbackFor = Exception.class)
    public ScrapeTaskDto createWebOptimizeTask(UUID requesterUserId, UUID videoItemId) {
        if (!mediaRuntimeConfigService.transcodeEnabled()) {
            throw new BusinessException(ErrorCode.CONFLICT, "媒体转码未启用，请在配置中心开启 media.transcode.enabled");
        }
        MediaVideoItem videoItem = mediaContentAccessService.requireReadableVideo(requesterUserId, videoItemId);
        UUID catalogOwnerUserId = videoItem.getOwnerUserId();
        UUID taskId = UUID.randomUUID();
        taskRecordService.createQueuedTask(
                taskId, requesterUserId, WEB_OPTIMIZE, QueueNames.VIDEO_TRANSCODE_ROUTING_KEY,
                "QUEUED", "FILE_NODE", videoItem.getFileNodeId(),
                Map.of(
                        "videoItemId", videoItemId.toString(),
                        "ownerUserId", catalogOwnerUserId.toString(),
                        "requesterUserId", requesterUserId.toString(),
                        "audioOnly", false,
                        "webOptimize", true
                ));
        TranscodeRequestedEvent event = new TranscodeRequestedEvent(
                taskId, videoItemId, catalogOwnerUserId, false, true);
        // 任务记录与 Outbox 投递行在同一事务提交，避免"记录已建而消息丢失"的僵尸任务。
        taskDispatchService.enqueue(
                taskId,
                QueueNames.TASK_EXCHANGE,
                QueueNames.VIDEO_TRANSCODE_ROUTING_KEY,
                event
        );
        return new ScrapeTaskDto(taskId, TaskStatus.QUEUED.getValue(), "Web 优化转码任务已进入队列");
    }

    /**
     * 创建媒体库扫描任务并投递到 Worker 异步执行，请求线程不扫描目录。
     */
    @Transactional(rollbackFor = Exception.class)
    public ScrapeTaskDto scanLibrary(UUID ownerUserId, MovieScanRequest request) {
        UUID taskId = UUID.randomUUID();
        taskRecordService.createQueuedTask(
                taskId,
                ownerUserId,
                MEDIA_SCAN,
                QueueNames.MEDIA_SCAN_ROUTING_KEY,
                Map.of(
                        "rootFolderId", request.rootFolderId() == null ? "" : request.rootFolderId().toString(),
                        "incremental", request.incremental()
                )
        );
        MediaLibraryScanRequestedEvent event = new MediaLibraryScanRequestedEvent(
                taskId,
                ownerUserId,
                request.rootFolderId(),
                request.incremental()
        );
        taskDispatchService.enqueue(
                taskId,
                QueueNames.TASK_EXCHANGE,
                QueueNames.MEDIA_SCAN_ROUTING_KEY,
                event
        );
        return new ScrapeTaskDto(taskId, TaskStatus.QUEUED.getValue(), "媒体库扫描任务已进入队列");
    }

    /**
     * Worker 执行媒体库扫描。
     *
     * @param event 扫描请求事件
     */
    public void executeScan(MediaLibraryScanRequestedEvent event) {
        MovieScanRequest request = new MovieScanRequest(event.rootFolderId(), event.incremental());
        ScanResult result = scan(event.ownerUserId(), request);
        taskRecordService.markCompleted(event.taskId(), result.toMap());
    }

    private ScanResult scan(UUID ownerUserId, MovieScanRequest request) {
        List<FileDescriptor> nodes = nodes(ownerUserId, request.rootFolderId());
        List<UUID> allFileNodeIds = nodes.stream()
                .filter(node -> NodeType.FILE.getValue().equals(node.nodeType()))
                .map(FileDescriptor::id)
                .toList();
        // 增量模式：跳过已有 MediaVideoItem 的文件
        // 全量模式：跳过已成功刮削（MATCHED）的文件
        Map<UUID, String> existingStatusMap = Collections.emptyMap();
        Set<UUID> existingFileNodeIds = Collections.emptySet();
        if (!allFileNodeIds.isEmpty()) {
            List<MediaVideoItem> existingItems = videoItemRepository.findByOwnerUserIdAndFileNodeIdIn(ownerUserId, allFileNodeIds);
            if (request.incremental()) {
                existingFileNodeIds = existingItems.stream()
                        .map(MediaVideoItem::getFileNodeId)
                        .collect(Collectors.toSet());
            } else {
                existingStatusMap = existingItems.stream()
                        .collect(Collectors.toMap(
                                MediaVideoItem::getFileNodeId,
                                MediaVideoItem::getMetadataStatus,
                                (l, r) -> l));
            }
        }
        int videoCount = 0;
        int registeredCount = 0;
        for (FileDescriptor node : nodes) {
            if (!NodeType.FILE.getValue().equals(node.nodeType())
                    || !fileNameParser.isVideoFile(node.name(), node.mimeType())) {
                continue;
            }
            videoCount++;
            if (request.incremental() && existingFileNodeIds.contains(node.id())) {
                continue;
            }
            if (!request.incremental() && MetadataStatus.MATCHED.getValue().equals(existingStatusMap.get(node.id()))) {
                continue;
            }
            scrapeService.registerPendingVideo(ownerUserId, node.id());
            registeredCount++;
        }
        return new ScanResult(nodes.size(), videoCount, registeredCount);
    }

    private List<FileDescriptor> nodes(UUID ownerUserId, UUID rootFolderId) {
        if (rootFolderId == null) {
            return fileMetadataQueryService.listOwnedActive(ownerUserId);
        }
        FileDescriptor root = fileMetadataQueryService.findOwnedActive(ownerUserId, rootFolderId)
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "扫描目录不存在"));
        if (NodeType.FILE.getValue().equals(root.nodeType())) {
            return List.of(root);
        }
        String prefix = root.normalizedPath() == null ? "" : root.normalizedPath();
        return fileMetadataQueryService.listOwnedActiveByPathPrefix(ownerUserId, prefix);
    }

    private String normalizeTaskType(String taskType) {
        if (taskType == null || taskType.isBlank() || "ALL".equalsIgnoreCase(taskType)) {
            return null;
        }
        return taskType.trim().toUpperCase(Locale.ROOT);
    }

    private record ScanResult(int scannedCount, int videoCount, int registeredCount) {
        Map<String, Object> toMap() {
            Map<String, Object> result = new LinkedHashMap<>();
            result.put("scannedCount", scannedCount);
            result.put("videoCount", videoCount);
            result.put("registeredCount", registeredCount);
            result.put("externalMetadataRequestCount", 0);
            return result;
        }
    }
}
