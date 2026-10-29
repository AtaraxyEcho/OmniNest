package com.omninest.modules.video.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.modules.file.domain.FileTypeCategories;
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
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.function.Function;
import java.util.function.LongSupplier;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 影视扫描、刮削和转码任务编排服务。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class MovieTaskService {
    private static final String MEDIA_SCAN = "MEDIA_SCAN";
    private static final String VIDEO_TRANSCODE = "VIDEO_TRANSCODE";
    private static final String WEB_OPTIMIZE = "WEB_OPTIMIZE";
    private static final int DEFAULT_TASK_LIMIT = 100;
    /** 单条 IN 查询的分批大小，低于 PostgreSQL 参数上限并留足余量。 */
    private static final int IN_QUERY_BATCH_SIZE = 1000;
    /** 扫描分页大小：每批处理完即释放，库规模不再决定常驻内存。 */
    private static final int SCAN_PAGE_SIZE = 500;
    /** 影视扫描只取视频分类，避免把同用户的照片、文档一起加载进内存。 */
    private static final List<String> VIDEO_SCAN_CATEGORIES = List.of(FileTypeCategories.VIDEO);

    /**
     * 转码类任务的在跑状态：同一请求者对同一源文件只允许排一份。
     */
    private static final Set<String> ACTIVE_TRANSCODE_STATUSES = Set.of(
            TaskStatus.QUEUED.getValue(),
            TaskStatus.RETRY_WAIT.getValue(),
            TaskStatus.RUNNING.getValue()
    );

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
        // 播放页会自动触发转码，那条路径没有入口限流：同一人反复回放同一部片
        // 会成倍排队，先复用仍在跑的同类任务。
        TaskRecord active = taskRecordService.findActiveResourceTask(
                requesterUserId, taskType, "FILE_NODE", videoItem.getFileNodeId(), ACTIVE_TRANSCODE_STATUSES)
                .orElse(null);
        if (active != null) {
            return new ScrapeTaskDto(active.getId(), active.getStatus(), "该影片的转码任务已在队列中");
        }
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
     * <p>执行前领取任务：重投消息只有一个 Worker 能进入扫描，任务状态也会从 QUEUED
     * 推进到执行中；排队期间被取消的任务不再执行。</p>
     *
     * @param event 扫描请求事件
     */
    public void executeScan(MediaLibraryScanRequestedEvent event) {
        if (!claimScanTask(event.taskId())) {
            return;
        }
        if (taskRecordService.isCancelled(event.taskId())) {
            taskRecordService.markCancelled(event.taskId());
            log.info("媒体库扫描任务已取消: taskId={}", event.taskId());
            return;
        }
        MovieScanRequest request = new MovieScanRequest(event.rootFolderId(), event.incremental());
        ScanResult result = scan(event.taskId(), event.ownerUserId(), request);
        if (taskRecordService.isCancelled(event.taskId())) {
            taskRecordService.markCancelled(event.taskId());
            log.info("媒体库扫描任务在执行期间被取消: taskId={}", event.taskId());
            return;
        }
        taskRecordService.markCompleted(event.taskId(), result.toMap());
    }

    private boolean claimScanTask(UUID taskId) {
        try {
            return taskRecordService.claimForExecution(taskId, "SCANNING");
        } catch (BusinessException exception) {
            if (ErrorCode.TASK_NOT_FOUND.equals(exception.errorCode())) {
                log.warn("媒体库扫描任务记录不存在，跳过消息: taskId={}", taskId);
                return false;
            }
            throw exception;
        }
    }

    private ScanResult scan(UUID taskId, UUID ownerUserId, MovieScanRequest request) {
        ScanAccumulator accumulator = new ScanAccumulator();
        if (request.rootFolderId() == null) {
            scanPaged(taskId, ownerUserId, request.incremental(), accumulator,
                    afterId -> fileMetadataQueryService.listOwnedActiveFilesByCategoriesAfterId(
                            ownerUserId, VIDEO_SCAN_CATEGORIES, afterId, SCAN_PAGE_SIZE),
                    () -> fileMetadataQueryService.countOwnedActiveFilesByCategories(
                            ownerUserId, VIDEO_SCAN_CATEGORIES));
        } else {
            FileDescriptor root = fileMetadataQueryService.findOwnedActive(ownerUserId, request.rootFolderId())
                    .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "扫描目录不存在"));
            if (NodeType.FILE.getValue().equals(root.nodeType())) {
                processVideoBatch(ownerUserId, List.of(root), request.incremental(), accumulator);
            } else {
                // 前缀必须带尾斜杠：否则扫描 /Movies 会把兄弟目录 /Movies_2026 里的文件一并登记进影视库
                String prefix = root.normalizedPath() == null ? "/" : root.normalizedPath() + "/";
                scanPaged(taskId, ownerUserId, request.incremental(), accumulator,
                        afterId -> fileMetadataQueryService.listOwnedActiveByPathPrefixAndCategoriesAfterId(
                                ownerUserId, root.spaceType(), prefix, VIDEO_SCAN_CATEGORIES,
                                afterId, SCAN_PAGE_SIZE),
                        () -> fileMetadataQueryService.countOwnedActiveByPathPrefixAndCategories(
                                ownerUserId, root.spaceType(), prefix, VIDEO_SCAN_CATEGORIES));
            }
        }
        return new ScanResult(accumulator.scanned, accumulator.videoCount,
                accumulator.registeredCount, accumulator.newlyRegisteredCount);
    }

    /**
     * 按 ID 游标分页扫描：每批处理完即释放，不再把全库文件加载进内存。
     */
    private void scanPaged(
            UUID taskId,
            UUID ownerUserId,
            boolean incremental,
            ScanAccumulator accumulator,
            Function<UUID, List<FileDescriptor>> pageLoader,
            LongSupplier totalSupplier
    ) {
        long total = Math.max(totalSupplier.getAsLong(), 1L);
        UUID afterId = new UUID(0L, 0L);
        while (true) {
            if (taskRecordService.isCancelled(taskId)) {
                return;
            }
            List<FileDescriptor> page = pageLoader.apply(afterId);
            if (page.isEmpty()) {
                return;
            }
            processVideoBatch(ownerUserId, page, incremental, accumulator);
            afterId = page.getLast().id();
            taskRecordService.updateExecution(taskId, "SCANNING",
                    (int) Math.min(95, accumulator.scanned * 100 / total));
            if (page.size() < SCAN_PAGE_SIZE) {
                return;
            }
        }
    }

    private void processVideoBatch(
            UUID ownerUserId, List<FileDescriptor> batch, boolean incremental, ScanAccumulator accumulator) {
        accumulator.scanned += batch.size();
        List<FileDescriptor> videoFiles = batch.stream()
                .filter(node -> NodeType.FILE.getValue().equals(node.nodeType()))
                .filter(node -> fileNameParser.isVideoFile(node.name(), node.mimeType()))
                .toList();
        accumulator.videoCount += videoFiles.size();
        if (videoFiles.isEmpty()) {
            return;
        }
        Map<UUID, MediaVideoItem> existingByFileNodeId = new LinkedHashMap<>();
        for (MediaVideoItem item : loadExistingItems(
                ownerUserId, videoFiles.stream().map(FileDescriptor::id).toList())) {
            existingByFileNodeId.putIfAbsent(item.getFileNodeId(), item);
        }
        List<FileDescriptor> pendingRegistration = new ArrayList<>();
        for (FileDescriptor node : videoFiles) {
            MediaVideoItem existing = existingByFileNodeId.get(node.id());
            if (incremental && existing != null) {
                continue;
            }
            if (!incremental && existing != null
                    && MetadataStatus.MATCHED.getValue().equals(existing.getMetadataStatus())) {
                continue;
            }
            pendingRegistration.add(node);
        }
        // registeredCount 保持历史口径 = 送入登记的条数；newlyRegisteredCount 才是新建行数。
        accumulator.registeredCount += pendingRegistration.size();
        accumulator.newlyRegisteredCount += scrapeService.registerPendingVideosBatch(
                ownerUserId, pendingRegistration, existingByFileNodeId);
    }

    /**
     * 分批查询已有影视条目：IN 参数超过 PostgreSQL 单语句上限会让扫描直接失败。
     */
    private List<MediaVideoItem> loadExistingItems(UUID ownerUserId, List<UUID> fileNodeIds) {
        List<MediaVideoItem> items = new ArrayList<>();
        for (int start = 0; start < fileNodeIds.size(); start += IN_QUERY_BATCH_SIZE) {
            int end = Math.min(start + IN_QUERY_BATCH_SIZE, fileNodeIds.size());
            items.addAll(videoItemRepository.findByOwnerUserIdAndFileNodeIdIn(
                    ownerUserId, fileNodeIds.subList(start, end)));
        }
        return items;
    }

    private String normalizeTaskType(String taskType) {
        if (taskType == null || taskType.isBlank() || "ALL".equalsIgnoreCase(taskType)) {
            return null;
        }
        return taskType.trim().toUpperCase(Locale.ROOT);
    }

    /** 扫描累计计数。 */
    private static final class ScanAccumulator {
        private int scanned;
        private int videoCount;
        private int registeredCount;
        private int newlyRegisteredCount;
    }

    private record ScanResult(int scannedCount, int videoCount, int registeredCount, int newlyRegisteredCount) {
        Map<String, Object> toMap() {
            Map<String, Object> result = new LinkedHashMap<>();
            result.put("scannedCount", scannedCount);
            result.put("videoCount", videoCount);
            result.put("registeredCount", registeredCount);
            result.put("newlyRegisteredCount", newlyRegisteredCount);
            result.put("externalMetadataRequestCount", 0);
            return result;
        }
    }
}
