package com.omninest.modules.photos.service;

import com.omninest.common.cache.ReadThroughCache;
import com.omninest.common.enums.ErrorCode;
import com.omninest.modules.media.domain.MetadataStatus;
import com.omninest.modules.task.domain.TaskRecord;
import com.omninest.modules.task.domain.TaskStatus;
import com.omninest.common.error.BusinessException;
import com.omninest.common.messaging.QueueNames;
import com.omninest.common.sync.SyncScope;
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
import com.omninest.modules.photos.event.PhotoIndexEvent;
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
import java.io.OutputStream;
import java.io.PushbackInputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.DigestInputStream;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HashMap;
import java.util.HexFormat;
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
    private final PhotoInputGuard inputGuard;
    private final PhotoSourceFileService sourceFileService;
    private final PhotoExifExtractor exifExtractor;
    private final PhotoThumbnailService thumbnailService;
    private final NotificationPublisher notificationService;
    private final TaskDispatchService taskDispatchService;
    private final PhotoRawPreviewService rawPreviewService;
    private final PhotosRuntimeConfigService photosRuntimeConfigService;
    private final FileQueryService fileQueryService;
    private final PhotoGeoService photoGeoService;
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
                            transactionTemplate.executeWithoutResult(status ->
                                    importPhotoFile(ownerUserId, file)
                            );
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
     * @param ownerUserId 当前用户 ID
     * @param fileNodeId 文件节点 ID
     */
    @Transactional(rollbackFor = Exception.class)
    public void importSinglePhoto(UUID ownerUserId, UUID fileNodeId) {
        FileDescriptor file = fileMetadataQueryService.findActiveById(fileNodeId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "文件不存在"));
        importPhotoFile(ownerUserId, file);
        syncEventService.invalidate(
                ownerUserId,
                SyncScope.PHOTOS,
                "PHOTO_LIBRARY",
                Map.of("source", "UPLOAD", "fileNodeId", fileNodeId.toString())
        );
        invalidateDashboardCache(ownerUserId);
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

    private void importPhotoFile(UUID ownerUserId, FileDescriptor file) {
        if ("webp".equals(fileDetector.extension(file.name()))) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "当前 Photos 不支持 WebP 文件");
        }
        var existing = photoItemRepository.findByOwnerUserIdAndFileNodeId(ownerUserId, file.id());
        if (existing.isPresent()) {
            // 历史无封面条目（如内容与扩展名不符曾被旧校验拒绝）在重扫时
            // 补投缩略图任务自愈，避免永久占位。
            PhotoItem present = existing.get();
            if (present.getCoverFileId() == null && file.currentObjectId() != null) {
                filePostProcessingTaskService.enqueueThumbnailIfAbsent(
                        thumbnailEvent(file, ownerUserId));
            }
            return;
        }
        PhotoItem photo = new PhotoItem();
        photo.setId(UUID.randomUUID());
        photo.setOwnerUserId(ownerUserId);
        photo.setFileNodeId(file.id());
        photo.setTitle(PhotoAdminSupport.titleFromFileName(file.name()));
        photo.setFormat(fileDetector.extension(file.name()));
        // RAW 预览需要真实文件，保留暂存路径；常规图片流式读取，
        // EXIF 提取与内容哈希共用一次下载，封面交给缩略图任务异步生成回填。
        boolean raw = fileDetector.isRaw(file.name());
        String contentHash;
        String motionKind = null;
        PhotoExifExtractor.ExifData exif;
        if (raw) {
            try (PhotoSourceFileService.StagedPhotoFile source = sourceFileService.stageReadable(
                    ownerUserId,
                    file.id()
            )) {
                photo.setFileSize(source.sizeBytes());
                try (InputStream input = Files.newInputStream(source.path())) {
                    exif = exifExtractor.extract(input);
                }
                inputGuard.validateDimensions(exif.width(), exif.height());
                applyExif(photo, exif);
                applyLocation(photo);
                if (!fileDetector.isDecodable(file.name())) {
                    photo.setCoverFileId(rawPreviewService.createPreview(
                            ownerUserId, photo.getId(), source.path()));
                }
                contentHash = computeSha256(source.path());
            } catch (IOException exception) {
                throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "照片源文件处理失败");
            }
        } else {
            try (FileContentStream content = fileQueryService.openReadableFileContent(ownerUserId, file.id());
                 DigestInputStream digestInput = new DigestInputStream(content.inputStream(), sha256Digest())) {
                photo.setFileSize(file.sizeBytes());
                // 先取头部魔数归一化 format：入口按声明 MIME 收件，扩展名
                // 可能与真实内容不符，后续处理与展示都以魔数为准。
                // pushback 仅是摘录流的包装，不拥有底层流生命周期：
                // 关闭它会连带关闭 digestInput，破坏后续尾部扫描与哈希。
                byte[] head = digestInput.readNBytes(CONTENT_PEEK_BYTES);
                String detectedFormat = inputGuard.detectContentFormat(head);
                if (detectedFormat != null) {
                    photo.setFormat(detectedFormat);
                }
                PushbackInputStream pushback = new PushbackInputStream(
                        digestInput, CONTENT_PEEK_BYTES);
                pushback.unread(head, 0, head.length);
                exif = exifExtractor.extract(pushback);
                inputGuard.validateDimensions(exif.width(), exif.height());
                applyExif(photo, exif);
                applyLocation(photo);
                // 流式哈希同时维护 4KB 尾部环形缓冲，供三星 SEF trailer 扫描，零额外 IO。
                byte[] tail = new byte[PhotoMotionTrailerScanner.TAIL_WINDOW_BYTES];
                byte[] chunk = new byte[READ_CHUNK_BYTES];
                int tailFilled = 0;
                int read;
                while ((read = digestInput.read(chunk)) != -1) {
                    tailFilled = appendTail(tail, tailFilled, chunk, read);
                }
                contentHash = HexFormat.of().formatHex(digestInput.getMessageDigest().digest());
                motionKind = resolveMotionKind(file.name(), exif.motion(), tail, tailFilled);
                if (motionKind != null) {
                    Map<String, Object> motion = new HashMap<>();
                    motion.put("kind", motionKind);
                    if (exif.motion().microVideoOffset() != null) {
                        motion.put("offsetBytes", exif.motion().microVideoOffset());
                    }
                    photo.getProviderMetadata().put("motion", motion);
                    photo.setMotionState(PhotoMotionVideoService.STATE_DETECTED);
                }
            } catch (IOException exception) {
                throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "照片源文件处理失败");
            }
        }
        photo.setMetadataStatus(exif.hasAnyValue()
                ? MetadataStatus.MATCHED.getValue()
                : MetadataStatus.PENDING.getValue());
        photo.getProviderMetadata().put("contentHash", contentHash);

        photoItemRepository.save(photo);

        UUID savedPhotoId = photo.getId();
        // 照片记录与 Outbox 投递行在同一事务提交，避免"记录已建而消息丢失"；
        // 索引事件无独立任务记录，Outbox 任务标识复用照片 ID。
        taskDispatchService.enqueue(
                savedPhotoId,
                QueueNames.TASK_EXCHANGE,
                QueueNames.PHOTO_INDEX_ROUTING_KEY,
                new PhotoIndexEvent(savedPhotoId, ownerUserId)
        );
        if (!raw && file.currentObjectId() != null) {
            // 封面不再同步生成，补投缩略图任务（含 active-task 去重）。
            filePostProcessingTaskService.enqueueThumbnailIfAbsent(
                    thumbnailEvent(file, ownerUserId));
            if (motionKind != null) {
                // 动态照片补投运动视频提取任务（含 active-task 去重）。
                filePostProcessingTaskService.enqueuePhotoMotionIfAbsent(
                        thumbnailEvent(file, ownerUserId));
            }
        }

        if (photosRuntimeConfigService.isAiEnabled()) {
            photoAiTaskService.queueSingleAnalysis(ownerUserId, savedPhotoId);
        }
    }

    private void applyLocation(PhotoItem photo) {
        if (photo.getGpsLatitude() == null || photo.getGpsLongitude() == null) {
            return;
        }
        Map<String, Object> geoInfo = photoGeoService.reverseGeocode(
                photo.getGpsLatitude(),
                photo.getGpsLongitude()
        );
        if (!geoInfo.isEmpty()) {
            photo.setGpsLocation(geoInfo);
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

    /** 新建 SHA-256 摘要器。 */
    private MessageDigest sha256Digest() {
        try {
            return MessageDigest.getInstance("SHA-256");
        } catch (NoSuchAlgorithmException exception) {
            throw new IllegalStateException("SHA-256 算法不可用", exception);
        }
    }

    /** 动态照片检测的流式读取块大小。 */
    private static final int READ_CHUNK_BYTES = 8192;

    /** 内容魔数探测的头部字节数，与 PhotoInputGuard 的魔数表保持一致。 */
    private static final int CONTENT_PEEK_BYTES = 16;

    /**
     * 把本次读取的字节追加进尾部环形缓冲，保留最近的窗口字节。
     *
     * @param tail 尾部缓冲
     * @param tailFilled 缓冲中的有效字节数
     * @param chunk 本次读取的数据
     * @param length 本次读取的有效长度
     * @return 更新后的有效字节数
     */
    private int appendTail(byte[] tail, int tailFilled, byte[] chunk, int length) {
        if (length >= tail.length) {
            System.arraycopy(chunk, length - tail.length, tail, 0, tail.length);
            return tail.length;
        }
        int overflow = tailFilled + length - tail.length;
        if (overflow > 0) {
            System.arraycopy(tail, overflow, tail, 0, tailFilled - overflow);
            tailFilled -= overflow;
        }
        System.arraycopy(chunk, 0, tail, tailFilled, length);
        return tailFilled + length;
    }

    /**
     * 解析动态照片类型：优先 XMP（GCamera 新旧标准），未命中时扫描三星 SEF trailer。
     * 仅对 JPEG 生效，RAW/HEIC 等格式不做检测。
     */
    private String resolveMotionKind(
            String fileName,
            PhotoExifExtractor.MotionInfo motionInfo,
            byte[] tail,
            int tailFilled
    ) {
        String extension = fileDetector.extension(fileName);
        if (!"jpg".equals(extension) && !"jpeg".equals(extension)) {
            return null;
        }
        if (motionInfo.detected()) {
            return motionInfo.microVideo() ? "MICRO_VIDEO" : "MOTION_PHOTO";
        }
        if (PhotoMotionTrailerScanner.hasSefTrailer(tail, tailFilled)) {
            return "SEF_TRAILER";
        }
        return null;
    }

    private void applyExif(PhotoItem photo, PhotoExifExtractor.ExifData exif) {
        photo.setWidth(exif.width());
        photo.setHeight(exif.height());
        photo.setOrientation(exif.orientation());
        photo.setDateTaken(exif.dateTaken());
        photo.setCameraMake(exif.cameraMake());
        photo.setCameraModel(exif.cameraModel());
        photo.setAperture(exif.aperture());
        photo.setShutterSpeed(exif.shutterSpeed());
        photo.setIso(exif.iso());
        photo.setFocalLength(exif.focalLength());
        photo.setGpsLatitude(exif.gpsLatitude());
        photo.setGpsLongitude(exif.gpsLongitude());
        photo.setFlash(exif.flash());
        photo.setWhiteBalance(exif.whiteBalance());
        photo.setMeteringMode(exif.meteringMode());
        photo.setLensModel(exif.lensModel());
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
        return fileMetadataQueryService.findActivePath(ownerUserId, normalizedPath)
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

    private String computeSha256(Path file) throws IOException {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            try (InputStream input = Files.newInputStream(file);
                 DigestInputStream digestInput = new DigestInputStream(input, digest)) {
                digestInput.transferTo(OutputStream.nullOutputStream());
            }
            return HexFormat.of().formatHex(digest.digest());
        } catch (NoSuchAlgorithmException exception) {
            throw new IllegalStateException("SHA-256 算法不可用", exception);
        }
    }
}
