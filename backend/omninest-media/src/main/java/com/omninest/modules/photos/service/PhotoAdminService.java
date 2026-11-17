package com.omninest.modules.photos.service;

import com.omninest.common.cache.ReadThroughCache;
import com.omninest.common.enums.ErrorCode;
import com.omninest.modules.media.domain.MetadataStatus;
import com.omninest.modules.task.domain.TaskRecord;
import com.omninest.modules.task.domain.TaskStatus;
import com.omninest.common.error.BusinessException;
import com.omninest.common.messaging.QueueNames;
import com.omninest.common.sync.SyncScope;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.dto.FileContentStream;
import com.omninest.modules.file.dto.FileDescriptor;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.support.TransactionTemplate;
import com.omninest.modules.file.dto.FileDownloadUrlDto;
import com.omninest.modules.file.event.FileUploadedEvent;
import com.omninest.modules.file.service.FileMetadataQueryService;
import com.omninest.modules.file.service.FilePostProcessingTaskService;
import com.omninest.modules.file.service.FileQueryService;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.notification.port.NotificationPublisher;
import com.omninest.modules.photos.domain.PhotoItem;
import com.omninest.modules.photos.domain.PhotoScanJob;
import com.omninest.modules.photos.dto.PhotoDtos.PhotoScanJobDto;
import com.omninest.modules.photos.event.PhotoScanEvent;
import com.omninest.modules.photos.event.PhotoThumbnailRegenerationEvent;
import com.omninest.modules.photos.repository.PhotoItemRepository;
import com.omninest.modules.photos.repository.PhotoScanJobRepository;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskHeartbeatRunner;
import com.omninest.modules.task.service.TaskRecordService;
import jakarta.annotation.PostConstruct;
import com.omninest.common.util.ThrowableDescriber;
import java.io.IOException;
import java.io.InputStream;
import java.io.PushbackInputStream;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.time.Instant;
import java.util.Objects;
import java.util.UUID;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.Semaphore;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.transaction.annotation.Transactional;

/**
 * 照片管理服务，负责扫描导入和候选文件查询。
 *
 * <p>遵循 MusicAdminService 的模式：
 * <ul>
 *   <li>{@link #importCandidates} — 列出尚未导入的图片文件</li>
 *   <li>{@link #createScanJob} — 批量导入所有图片文件，提取 EXIF 并生成缩略图</li>
 *   <li>{@link #scanJob} — 查询扫描任务状态</li>
 * </ul>
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class PhotoAdminService {
    /** 照片扫描并发；默认 3，保持 Worker 8 个数据库连接中至少一半给心跳与其他消费者。 */
    @Value("${omninest.concurrency.photo-scan:3}")
    int scanConcurrency = 3;

    /** 扫描按主键游标分批读取图片节点，避免把全库实体一次性载入内存。 */
    private static final int SCAN_PAGE_SIZE = 500;

    private static final List<String> ACTIVE_TASK_STATUSES = List.of(
            TaskStatus.QUEUED.getValue(),
            TaskStatus.RUNNING.getValue(),
            TaskStatus.RETRY_WAIT.getValue()
    );

    private final PhotoScanJobRepository scanJobRepository;
    private final PhotoItemRepository photoItemRepository;
    private final FileMetadataQueryService fileMetadataQueryService;
    private final PhotoFileDetector fileDetector;
    private final PhotoSourceFileService sourceFileService;
    private final PhotoImportPreparer photoImportPreparer;
    private final PhotoThumbnailService thumbnailService;
    private final NotificationPublisher notificationService;
    private final TaskDispatchService taskDispatchService;
    private final PhotoRawPreviewService rawPreviewService;
    private final FileQueryService fileQueryService;
    private final PhotoAiTaskService photoAiTaskService;
    private final TaskRecordService taskRecordService;
    private final TaskHeartbeatRunner taskHeartbeatRunner;
    private final FilePostProcessingTaskService filePostProcessingTaskService;
    private final MediaSyncEventService syncEventService;
    private final ReadThroughCache readThroughCache;
    private final PlatformTransactionManager transactionManager;
    private TransactionTemplate transactionTemplate;

    /**
     * 初始化逐文件独立事务模板。
     */
    @PostConstruct
    void initTransactionTemplate() {
        this.transactionTemplate = new TransactionTemplate(transactionManager);
        this.transactionTemplate.setPropagationBehavior(
                TransactionDefinition.PROPAGATION_REQUIRES_NEW
        );
    }

    /**
     * 创建扫描任务，发布到 RabbitMQ 异步执行。
     *
     * @param ownerUserId 当前用户 ID
     * @return 扫描任务
     */
    @Transactional(rollbackFor = Exception.class)
    public PhotoScanJobDto createScanJob(UUID ownerUserId) {
        // 已有排队/执行中的扫描直接复用，避免连点把全库扫描刷进队列耗尽 Worker IO。
        PhotoScanJob existing = taskRecordService
                .findActiveTaskForOwner(ownerUserId, "PHOTO_SCAN", ACTIVE_TASK_STATUSES)
                .flatMap(task -> scanJobRepository.findByIdAndOwnerUserId(task.getId(), ownerUserId))
                .orElse(null);
        if (existing != null) {
            return PhotoAdminSupport.toDto(existing);
        }
        UUID taskId = UUID.randomUUID();
        taskRecordService.createQueuedTask(taskId, ownerUserId, "PHOTO_SCAN", QueueNames.PHOTO_SCAN_ROUTING_KEY, Map.of(
                "jobId", taskId.toString(),
                "ownerUserId", ownerUserId.toString()
        ));
        PhotoScanJob job = new PhotoScanJob();
        job.setId(taskId);
        job.setTaskId(taskId);
        job.setOwnerUserId(ownerUserId);
        job.setStatus(TaskStatus.QUEUED.getValue());
        job.setMessage("扫描任务已排队");
        scanJobRepository.save(job);

        PhotoScanEvent event = new PhotoScanEvent(job.getId(), ownerUserId);
        // 任务记录与 Outbox 投递行在同一事务提交，避免"记录已建而消息丢失"的僵尸任务。
        taskDispatchService.enqueue(
                taskId,
                QueueNames.TASK_EXCHANGE,
                QueueNames.PHOTO_SCAN_ROUTING_KEY,
                event
        );

        return PhotoAdminSupport.toDto(job);
    }

    /**
     * 执行扫描任务（由 Worker 消费者调用）。
     *
     * @param jobId 扫描任务 ID
     * @param ownerUserId 当前用户 ID
     */
    public void executeScanJob(UUID jobId, UUID ownerUserId) {
        PhotoScanJob job = scanJobRepository.findById(jobId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "扫描任务不存在"));
        if (!taskRecordService.claimForExecution(jobId, "SCANNING")) {
            return;
        }

        job.setStatus(TaskStatus.RUNNING.getValue());
        job.setMessage("相册扫描中");
        // executeScanJob 无外层事务，job 为脱管实体：merge 返回的新受管实例
        // 才携带推进后的 version；不接住返回值则收尾保存仍带旧版本，
        // 必然触发 StaleObjectStateException（同 D-009）。
        job = scanJobRepository.save(job);

        int imported = 0;
        try {
            // 个人相册扫描只处理本人文件：共享空间里他人的图片会以扫描者身份
            // 克隆出影子 PhotoItem，回收站清理时因底层 FileNode 不属于本人而永久失败。
            long totalFiles = fileMetadataQueryService.countOwnedImages(ownerUserId);
            int totalForProgress = (int) Math.min(totalFiles, Integer.MAX_VALUE);
            AtomicInteger processedCounter = new AtomicInteger();
            AtomicInteger importedCounter = new AtomicInteger();
            // 扫描可能持续数十分钟；心跳线程按已处理数量刷新任务心跳，避免被恢复调度器
            // 判定为僵尸任务后重复并发投递。
            try (TaskHeartbeatRunner.Heartbeat ignored = taskHeartbeatRunner.start(
                    jobId,
                    () -> PhotoAdminSupport.progressPercent(processedCounter.get(), totalForProgress))) {
                UUID afterId = new UUID(0L, 0L);
                while (true) {
                    List<FileDescriptor> nodes = fileMetadataQueryService.listOwnedImagesPage(
                            ownerUserId, afterId, SCAN_PAGE_SIZE);
                    if (nodes.isEmpty()) {
                        break;
                    }
                    importScanPage(ownerUserId, nodes, importedCounter);
                    processedCounter.addAndGet(nodes.size());
                    taskRecordService.updateProgress(
                            jobId, PhotoAdminSupport.progressPercent(processedCounter.get(), totalForProgress));
                    afterId = nodes.getLast().id();
                    if (nodes.size() < SCAN_PAGE_SIZE) {
                        break;
                    }
                }
            }
            imported = importedCounter.get();

            final int importedCount = imported;
            // 同步事件记录器要求外层事务（MANDATORY 传播），而 executeScanJob
            // 本体刻意无事务（逐文件独立提交），此前裸调 invalidate 在完成边缘
            // 触发 IllegalTransactionStateException（D-009）；收尾状态、失效事件
            // 与终态保存改在独立短事务内原子提交。
            final PhotoScanJob completedJob = job;
            transactionTemplate.executeWithoutResult(status -> {
                completedJob.setStatus(TaskStatus.COMPLETED.getValue());
                completedJob.setScannedFiles(importedCount);
                completedJob.setMessage("相册扫描完成，已处理 " + importedCount + " 个图片文件");
                taskRecordService.markCompleted(jobId, Map.of("imported", importedCount));
                syncEventService.invalidate(
                        ownerUserId,
                        SyncScope.PHOTOS,
                        "PHOTO_LIBRARY",
                        Map.of("source", "SCAN", "imported", importedCount)
                );
                scanJobRepository.save(completedJob);
            });
            invalidateDashboardCache(ownerUserId);
            // 发送扫描完成通知
            notificationService.notifyOrLog(ownerUserId, "TASK_COMPLETED",
                    "照片扫描完成", "已处理 " + imported + " 个图片文件",
                    Map.of("jobId", jobId.toString()));
        } catch (Exception ex) {
            log.error("照片扫描任务执行失败: jobId={}", jobId, ex);
            // 失败路径按 id 重新加载最新版本实体后再写终态，避免收尾保存
            // 携带旧版本触发乐观锁异常，使任务行停留在 RUNNING。
            PhotoScanJob failedJob = scanJobRepository.findById(jobId).orElse(job);
            failedJob.setStatus(TaskStatus.FAILED.getValue());
            failedJob.setMessage("扫描失败: " + ex.getMessage());
            scanJobRepository.save(failedJob);
            taskRecordService.markFailed(jobId, ex.getMessage(), ThrowableDescriber.describe(ex));
            // 重试由消费者裁决；只在重试额度耗尽时通知，避免每次失败重复打扰用户。
            if (taskRecordService.hasExhaustedRetries(jobId)) {
                notificationService.notifyOrLog(ownerUserId, "TASK_FAILED",
                        "照片扫描失败", "扫描失败: " + ex.getMessage(),
                        Map.of("jobId", jobId.toString()));
            }
            throw ex instanceof RuntimeException runtimeException
                    ? runtimeException
                    : new IllegalStateException(ex.getMessage(), ex);
        }
    }

    /**
     * 导入一页图片文件；仍保持逐文件独立事务与有限并发。
     *
     * <p>事务边界由 {@link #importPhotoFile} 自己收口：远程读取与派生写入在事务外，
     * 只有实体落库与任务登记进短事务。</p>
     */
    private void importScanPage(
            UUID ownerUserId,
            List<FileDescriptor> nodes,
            AtomicInteger importedCounter
    ) {
        Semaphore scanPermits = new Semaphore(Math.max(1, scanConcurrency));
        try (ExecutorService executor = Executors.newVirtualThreadPerTaskExecutor()) {
            List<Future<?>> futures = nodes.stream()
                    .<Future<?>>map(file -> executor.submit(() -> {
                        scanPermits.acquireUninterruptibly();
                        try {
                            importPhotoFile(ownerUserId, file);
                            importedCounter.incrementAndGet();
                        } catch (Exception fileEx) {
                            log.warn("单个文件导入失败，跳过: fileNodeId={}, error={}",
                                    file.id(), fileEx.getMessage());
                        } finally {
                            scanPermits.release();
                        }
                    }))
                    .toList();
            for (Future<?> future : futures) {
                try {
                    future.get();
                } catch (InterruptedException exception) {
                    Thread.currentThread().interrupt();
                    throw new IllegalStateException("照片扫描等待并发结果时被中断", exception);
                } catch (ExecutionException exception) {
                    throw new IllegalStateException("照片扫描并发执行失败", exception.getCause());
                }
            }
        }
    }

    /**
     * 查询扫描任务状态。
     *
     * @param ownerUserId 当前用户 ID
     * @param jobId 扫描任务 ID
     * @return 扫描任务状态
     */
    @Transactional(readOnly = true)
    public PhotoScanJobDto scanJob(UUID ownerUserId, UUID jobId) {
        return scanJobRepository.findByIdAndOwnerUserId(jobId, ownerUserId)
                .map(PhotoAdminSupport::toDto)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "扫描任务不存在"));
    }

    /**
     * 导入单张照片（供自动导入调用）。
     * 查找 FileNode 并调用内部导入逻辑，幂等安全（已导入则跳过）。
     *
     * <p>不能再声明 {@code @Transactional}：方法体里的原图下载与 RAW 预览会在
     * 持有连接的情况下再申请 {@code REQUIRES_NEW} 连接，上传高峰时同样会拖垮
     * Hikari 池。失效事件仍与照片行同事务提交。</p>
     *
     * @param ownerUserId 当前用户 ID
     * @param fileNodeId 文件节点 ID
     */
    public void importSinglePhoto(UUID ownerUserId, UUID fileNodeId) {
        FileDescriptor file = fileMetadataQueryService.findActiveById(fileNodeId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "文件不存在"));
        validatePhotoFormat(file);
        PhotoImportPreparer.PreparedPhotoImport prepared = preparePhotoIfAbsent(ownerUserId, file);
        transactionTemplate.executeWithoutResult(status -> {
            persistPhotoImport(ownerUserId, file, prepared);
            syncEventService.invalidate(
                    ownerUserId,
                    SyncScope.PHOTOS,
                    "PHOTO_LIBRARY",
                    Map.of("source", "UPLOAD", "fileNodeId", fileNodeId.toString())
            );
            invalidateDashboardCache(ownerUserId);
        });
    }

    /**
     * 将异步缩略图任务生成的派生文件回填到照片记录，避免首次导入时永久缺少封面。
     *
     * @param ownerUserId 照片所有者
     * @param fileNodeId 原始文件节点
     * @param coverFileId 派生缩略图文件节点
     */
    @Transactional(rollbackFor = Exception.class)
    public void attachCoverIfMissing(UUID ownerUserId, UUID fileNodeId, UUID coverFileId) {
        if (coverFileId == null) {
            return;
        }
        photoItemRepository.findByOwnerUserIdAndFileNodeId(ownerUserId, fileNodeId)
                .filter(photo -> photo.getCoverFileId() == null)
                .ifPresent(photo -> {
                    photo.setCoverFileId(coverFileId);
                    photoItemRepository.save(photo);
                    invalidateDashboardCache(ownerUserId);
                    syncEventService.invalidate(
                            ownerUserId,
                            SyncScope.PHOTOS,
                            "PHOTO_LIBRARY",
                            Map.of("source", "THUMBNAIL", "fileNodeId", fileNodeId.toString())
                    );
                });
    }

    /**
     * 导入单个图片文件。
     *
     * <p>两段式：{@link PhotoImportPreparer} 在事务外完成对象存储下载、EXIF 解析、
     * RAW 预览生成与逆地理编码；{@link #persistPhotoImport} 在短事务里只写实体与
     * 投递任务。合成一段会把连接池钉死——RAW 预览走 {@code REQUIRES_NEW}，必须在
     * 已持有外层连接的情况下再申请第二条，扫描并发 3~4 时 worker 仅有的 6 条连接
     * 会全部卡在"等第二条连接"上。</p>
     */
    private void importPhotoFile(UUID ownerUserId, FileDescriptor file) {
        validatePhotoFormat(file);
        PhotoImportPreparer.PreparedPhotoImport prepared = preparePhotoIfAbsent(ownerUserId, file);
        transactionTemplate.executeWithoutResult(status ->
                persistPhotoImport(ownerUserId, file, prepared));
    }

    /**
     * 查询已导入状态，仅在缺失时才做事务外预计算。
     *
     * @return 待落库结果；{@code null} 表示该文件已导入
     */
    private PhotoImportPreparer.PreparedPhotoImport preparePhotoIfAbsent(
            UUID ownerUserId,
            FileDescriptor file
    ) {
        if (photoItemRepository.findByOwnerUserIdAndFileNodeId(ownerUserId, file.id()).isPresent()) {
            return null;
        }
        return photoImportPreparer.prepare(ownerUserId, file);
    }

    /**
     * 在短事务内落库并登记后续任务。
     *
     * @param prepared 事务外预计算结果；{@code null} 表示已导入，仅做封面自愈
     */
    private void persistPhotoImport(
            UUID ownerUserId,
            FileDescriptor file,
            PhotoImportPreparer.PreparedPhotoImport prepared
    ) {
        if (prepared == null) {
            // 历史无封面条目（如内容与扩展名不符曾被旧校验拒绝）在重扫时
            // 补投缩略图任务自愈，避免永久占位。
            photoItemRepository.findByOwnerUserIdAndFileNodeId(ownerUserId, file.id())
                    .filter(present -> present.getCoverFileId() == null && file.currentObjectId() != null)
                    .ifPresent(present -> filePostProcessingTaskService.enqueueThumbnailIfAbsent(
                            thumbnailEvent(file, ownerUserId)));
            return;
        }
        // 同一文件被并发导入时以先落库者为准：预计算在事务外完成，
        // 期间可能有另一条路径已经写入，这里再复核一次避免撞唯一键。
        if (photoItemRepository.findByOwnerUserIdAndFileNodeId(ownerUserId, file.id()).isPresent()) {
            return;
        }
        PhotoItem photo = prepared.photo();
        photoItemRepository.save(photo);
        if (prepared.enqueuePostProcessing()) {
            // 封面不再同步生成，补投缩略图任务（含 active-task 去重）。
            filePostProcessingTaskService.enqueueThumbnailIfAbsent(
                    thumbnailEvent(file, ownerUserId));
            if (prepared.motionKind() != null) {
                // 动态照片补投运动视频提取任务（含 active-task 去重）。
                filePostProcessingTaskService.enqueuePhotoMotionIfAbsent(
                        thumbnailEvent(file, ownerUserId));
            }
        }
        if (prepared.aiAnalysisEnabled()) {
            photoAiTaskService.queueSingleAnalysis(ownerUserId, photo.getId());
        }
    }

    private void validatePhotoFormat(FileDescriptor file) {
        if ("webp".equals(fileDetector.extension(file.name()))) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "当前 Photos 不支持 WebP 文件");
        }
    }

    private void invalidateDashboardCache(UUID ownerUserId) {
        readThroughCache.invalidate("omninest:dashboard:photo:" + ownerUserId);
    }

    /**
     * 构造补投缩略图任务所需的最小上传事件。
     *
     * <p>缩略图消费者通过 provider 无关的源文件服务读取内容，
     * 不依赖对象存储定位信息。</p>
     */
    private FileUploadedEvent thumbnailEvent(FileDescriptor file, UUID ownerUserId) {
        return new FileUploadedEvent(
                file.id(),
                file.currentObjectId(),
                ownerUserId,
                "",
                "",
                file.name(),
                file.mimeType(),
                file.sizeBytes(),
                Instant.now()
        );
    }

    /**
     * 获取 RAW 文件预览的下载 URL。
     * 如果照片不是 RAW 格式或预览不存在，返回 null。
     *
     * @param ownerUserId 当前用户 ID
     * @param photoId 照片 ID
     * @return RAW 预览下载 URL，不存在时返回 null
     */
    @Transactional(readOnly = true)
    public String getRawPreviewUrl(UUID ownerUserId, UUID photoId) {
        PhotoItem photo = photoItemRepository.findByOwnerUserIdAndId(ownerUserId, photoId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "照片不存在"));
        String normalizedPath = "/.metadata/PHOTO_ITEM/" + photoId + "/RAW_PREVIEW/" + photoId + "_raw_preview.jpg";
        return fileMetadataQueryService.findActivePath(ownerUserId, SpaceType.PERSONAL, normalizedPath)
                .map(node -> {
                    FileDownloadUrlDto url = fileQueryService.createDownloadUrlAs(ownerUserId, node.id());
                    return url.downloadUrl();
                })
                .orElse(null);
    }

    /**
     * 创建缩略图重生成任务，发布到 RabbitMQ 异步执行。
     *
     * @param ownerUserId 当前用户 ID
     * @return 任务 ID
     */
    @Transactional(rollbackFor = Exception.class)
    public UUID createThumbnailRegenerationTask(UUID ownerUserId) {
        UUID existingTaskId = taskRecordService
                .findActiveTaskForOwner(ownerUserId, "PHOTO_THUMBNAILS", ACTIVE_TASK_STATUSES)
                .map(TaskRecord::getId)
                .orElse(null);
        if (existingTaskId != null) {
            return existingTaskId;
        }
        UUID taskId = UUID.randomUUID();
        taskRecordService.createQueuedTask(
                taskId,
                ownerUserId,
                "PHOTO_THUMBNAILS",
                QueueNames.PHOTO_THUMBNAILS_ROUTING_KEY,
                Map.of("ownerUserId", ownerUserId.toString())
        );
        PhotoThumbnailRegenerationEvent event = new PhotoThumbnailRegenerationEvent(taskId, ownerUserId);
        // 任务记录与 Outbox 投递行在同一事务提交，避免"记录已建而消息丢失"的僵尸任务。
        taskDispatchService.enqueue(
                taskId,
                QueueNames.TASK_EXCHANGE,
                QueueNames.PHOTO_THUMBNAILS_ROUTING_KEY,
                event
        );
        return taskId;
    }

    /**
     * 执行缩略图重生成任务（由 Worker 消费者调用）。
     *
     * <p>逐张处理缺失封面的照片，单张失败仅记录并继续；进度实时上报任务记录。</p>
     *
     * @param taskId 任务 ID
     * @param ownerUserId 当前用户 ID
     */
    public void executeThumbnailRegeneration(UUID taskId, UUID ownerUserId) {
        if (!taskRecordService.claimForExecution(taskId, "PROCESSING")) {
            return;
        }
        // 按 ID 游标分批：失败的照片仍留在"缺失"集合里，只靠重查会反复取到同一批。
        int total = (int) Math.min(Integer.MAX_VALUE, photoItemRepository.countMissingCover(ownerUserId));
        int processed = 0;
        int regenerated = 0;
        int lastReported = -1;
        try {
            UUID afterId = new UUID(0L, 0L);
            while (true) {
                List<UUID> batch = photoItemRepository.findIdsMissingCoverAfter(
                        ownerUserId, afterId, PageRequest.of(0, SCAN_PAGE_SIZE));
                if (batch.isEmpty()) {
                    break;
                }
                regenerated += regenerateCoverBatch(ownerUserId, batch);
                processed += batch.size();
                int percent = PhotoAdminSupport.progressPercent(processed, Math.max(total, processed));
                if (percent != lastReported && (processed % 25 == 0 || processed >= total)) {
                    taskRecordService.updateProgress(taskId, percent);
                    lastReported = percent;
                }
                if (batch.size() < SCAN_PAGE_SIZE) {
                    break;
                }
                afterId = batch.get(batch.size() - 1);
            }
            taskRecordService.updateProgress(taskId, 100);
            taskRecordService.markCompleted(taskId, Map.of("regenerated", regenerated));
            invalidateDashboardCache(ownerUserId);
            syncEventService.invalidate(
                    ownerUserId,
                    SyncScope.PHOTOS,
                    "PHOTO_LIBRARY",
                    Map.of("source", "THUMBNAIL_REGENERATE", "regenerated", regenerated)
            );
            log.info("缩略图重新生成完成: ownerUserId={}, total={}, regenerated={}", ownerUserId, total, regenerated);
        } catch (RuntimeException ex) {
            taskRecordService.markFailed(taskId, ex.getMessage(), ThrowableDescriber.describe(ex));
            throw ex;
        }
    }

    /** 处理一批缺失封面的照片，返回成功生成的数量；批量预读避免 N+1，单张失败只记录。 */
    private int regenerateCoverBatch(UUID ownerUserId, List<UUID> photoIds) {
        Map<UUID, PhotoItem> photosById = photoItemRepository.findAllById(photoIds).stream()
                .filter(item -> ownerUserId.equals(item.getOwnerUserId()))
                .collect(Collectors.toMap(PhotoItem::getId, item -> item));
        List<UUID> fileNodeIds = photosById.values().stream()
                .map(PhotoItem::getFileNodeId)
                .filter(Objects::nonNull)
                .toList();
        Map<UUID, FileDescriptor> filesById = fileMetadataQueryService.findAllByIds(fileNodeIds).stream()
                .collect(Collectors.toMap(FileDescriptor::id, file -> file));
        int regenerated = 0;
        for (UUID photoId : photoIds) {
            PhotoItem photo = photosById.get(photoId);
            if (photo == null || photo.getCoverFileId() != null) {
                continue;
            }
            FileDescriptor file = filesById.get(photo.getFileNodeId());
            if (file == null) {
                continue;
            }
            try (PhotoSourceFileService.StagedPhotoFile source = sourceFileService.stageReadable(
                    ownerUserId,
                    file.id()
            )) {
                UUID coverFileId = createCover(ownerUserId, photo, file, source);
                if (coverFileId != null) {
                    photo.setCoverFileId(coverFileId);
                    photoItemRepository.save(photo);
                    regenerated++;
                }
            } catch (Exception exception) {
                // 单张损坏图片的解码/IO 异常不能中断整批任务；记录后继续下一张。
                log.warn("缩略图重生成失败: fileNodeId={}, errorType={}, message={}",
                        file.id(), exception.getClass().getSimpleName(), exception.getMessage());
            }
        }
        return regenerated;
    }

    /** 为重生成流程创建封面：可解码图片生成缩略图，RAW 生成预览图；无法生成时返回 null。 */
    private UUID createCover(
            UUID ownerUserId,
            PhotoItem photo,
            FileDescriptor file,
            PhotoSourceFileService.StagedPhotoFile source
    ) {
        UUID coverFileId = null;
        if (fileDetector.isDecodable(source.fileName())) {
            coverFileId = thumbnailService.generateAndStoreFile(
                    ownerUserId,
                    file.id(),
                    source.path(),
                    source.fileName()
            );
        }
        if (coverFileId == null && source.raw()) {
            coverFileId = rawPreviewService.createPreview(ownerUserId, photo.getId(), source.path());
        }
        return coverFileId;
    }

}
