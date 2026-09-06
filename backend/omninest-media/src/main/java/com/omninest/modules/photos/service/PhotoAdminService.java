package com.omninest.modules.photos.service;

import com.omninest.common.cache.ReadThroughCache;
import com.omninest.common.enums.ErrorCode;
import com.omninest.modules.media.domain.MetadataStatus;
import com.omninest.modules.task.domain.TaskStatus;
import com.omninest.common.error.BusinessException;
import com.omninest.common.messaging.DomainEventPublisher;
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
import com.omninest.modules.file.service.FilePermissionService;
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
import com.omninest.modules.task.service.TaskRecordService;
import jakarta.annotation.PostConstruct;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.DigestInputStream;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HexFormat;
import java.util.List;
import java.util.Map;
import java.time.Instant;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

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

    private final PhotoScanJobRepository scanJobRepository;
    private final PhotoItemRepository photoItemRepository;
    private final FileMetadataQueryService fileMetadataQueryService;
    private final PhotoFileDetector fileDetector;
    private final PhotoInputGuard inputGuard;
    private final PhotoSourceFileService sourceFileService;
    private final PhotoExifExtractor exifExtractor;
    private final PhotoThumbnailService thumbnailService;
    private final FilePermissionService filePermissionService;
    private final NotificationPublisher notificationService;
    private final DomainEventPublisher eventPublisher;
    private final PhotoRawPreviewService rawPreviewService;
    private final PhotosRuntimeConfigService photosRuntimeConfigService;
    private final FileQueryService fileQueryService;
    private final PhotoGeoService photoGeoService;
    private final PhotoAiTaskService photoAiTaskService;
    private final TaskRecordService taskRecordService;
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

        // 事务提交后再发布消息，避免 Worker 在事务提交前查询导致"任务不存在"
        TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
            @Override
            public void afterCommit() {
                eventPublisher.publishTask(
                        QueueNames.PHOTO_SCAN_ROUTING_KEY,
                        new PhotoScanEvent(job.getId(), ownerUserId));
            }
        });

        return toDto(job);
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
        scanJobRepository.save(job);

        int imported = 0;
        try {
            List<FileDescriptor> ownedNodes = fileMetadataQueryService.listOwnedImages(ownerUserId);
            List<FileDescriptor> allSharedNodes = fileMetadataQueryService.listSharedImagesVisibleToUser(ownerUserId);
            var viewableSharedFileIds = filePermissionService.resolveViewableFileIds(
                    allSharedNodes.stream().map(FileDescriptor::id).toList(), ownerUserId);
            List<FileDescriptor> sharedNodes = allSharedNodes.stream()
                    .filter(node -> viewableSharedFileIds.contains(node.id()))
                    .toList();

            List<FileDescriptor> nodes = new ArrayList<>(ownedNodes);
            nodes.addAll(sharedNodes);

            for (FileDescriptor file : nodes) {
                try {
                    // 逐文件独立事务：单文件失败不阻塞整库扫描。
                    transactionTemplate.executeWithoutResult(status ->
                            importPhotoFile(ownerUserId, file)
                    );
                    imported++;
                } catch (Exception fileEx) {
                    log.warn("单个文件导入失败，跳过: fileNodeId={}, error={}", file.id(), fileEx.getMessage());
                }
            }

            job.setStatus(TaskStatus.COMPLETED.getValue());
            job.setScannedFiles(imported);
            job.setMessage("相册扫描完成，已处理 " + imported + " 个图片文件");
            taskRecordService.markCompleted(jobId, Map.of("imported", imported));
            syncEventService.invalidate(
                    ownerUserId,
                    SyncScope.PHOTOS,
                    "PHOTO_LIBRARY",
                    Map.of("source", "SCAN", "imported", imported)
            );
            invalidateDashboardCache(ownerUserId);
            // 发送扫描完成通知
            notificationService.notifyOrLog(ownerUserId, "TASK_COMPLETED",
                    "照片扫描完成", "已处理 " + imported + " 个图片文件",
                    Map.of("jobId", jobId.toString()));
        } catch (Exception ex) {
            log.error("照片扫描任务执行失败: jobId={}", jobId, ex);
            job.setStatus(TaskStatus.FAILED.getValue());
            job.setMessage("扫描失败: " + ex.getMessage());
            taskRecordService.markFailed(jobId, ex.getMessage());
            // 发送扫描失败通知
            notificationService.notifyOrLog(ownerUserId, "TASK_FAILED",
                    "照片扫描失败", "扫描失败: " + ex.getMessage(),
                    Map.of("jobId", jobId.toString()));
        }
        scanJobRepository.save(job);
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
                .map(this::toDto)
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
            return;
        }
        PhotoItem photo = new PhotoItem();
        photo.setId(UUID.randomUUID());
        photo.setOwnerUserId(ownerUserId);
        photo.setFileNodeId(file.id());
        photo.setTitle(titleFromFileName(file.name()));
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
                exif = exifExtractor.extract(digestInput);
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

        // 事务提交后再发布消息，避免 Worker 在事务提交前查询导致"照片不存在"
        UUID savedPhotoId = photo.getId();
        final String detectedMotionKind = motionKind;
        TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
            @Override
            public void afterCommit() {
                eventPublisher.publishTask(
                        QueueNames.PHOTO_INDEX_ROUTING_KEY,
                        new PhotoIndexEvent(savedPhotoId, ownerUserId)
                );
                if (!raw && file.currentObjectId() != null) {
                    // 封面不再同步生成，补投缩略图任务（含 active-task 去重）。
                    filePostProcessingTaskService.enqueueThumbnailIfAbsent(
                            thumbnailEvent(file, ownerUserId));
                    if (detectedMotionKind != null) {
                        // 动态照片补投运动视频提取任务（含 active-task 去重）。
                        filePostProcessingTaskService.enqueuePhotoMotionIfAbsent(
                                thumbnailEvent(file, ownerUserId));
                    }
                }
            }
        });

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
                    FileDownloadUrlDto url = fileQueryService.createDownloadUrl(ownerUserId, node.id());
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
        UUID taskId = UUID.randomUUID();
        taskRecordService.createQueuedTask(
                taskId,
                ownerUserId,
                "PHOTO_THUMBNAILS",
                QueueNames.PHOTO_THUMBNAILS_ROUTING_KEY,
                Map.of("ownerUserId", ownerUserId.toString())
        );
        TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
            @Override
            public void afterCommit() {
                eventPublisher.publishTask(
                        QueueNames.PHOTO_THUMBNAILS_ROUTING_KEY,
                        new PhotoThumbnailRegenerationEvent(taskId, ownerUserId));
            }
        });
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
        List<UUID> photoIds = photoItemRepository.findIdsMissingCover(ownerUserId);
        int total = photoIds.size();
        int regenerated = 0;
        try {
            for (int index = 0; index < total; index++) {
                PhotoItem photo = photoItemRepository.findById(photoIds.get(index))
                        .filter(item -> ownerUserId.equals(item.getOwnerUserId()))
                        .orElse(null);
                if (photo == null || photo.getCoverFileId() != null) {
                    taskRecordService.updateProgress(taskId, progressPercent(index + 1, total));
                    continue;
                }
                FileDescriptor file = fileMetadataQueryService.findById(photo.getFileNodeId()).orElse(null);
                if (file == null) {
                    taskRecordService.updateProgress(taskId, progressPercent(index + 1, total));
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
                } catch (BusinessException exception) {
                    log.warn("缩略图源文件处理失败: fileNodeId={}, error={}", file.id(), exception.getMessage());
                }
                taskRecordService.updateProgress(taskId, progressPercent(index + 1, total));
            }
            taskRecordService.markCompleted(taskId, Map.of("regenerated", regenerated));
            log.info("缩略图重新生成完成: ownerUserId={}, total={}, regenerated={}", ownerUserId, total, regenerated);
        } catch (RuntimeException ex) {
            taskRecordService.markFailed(taskId, ex.getMessage());
            throw ex;
        }
    }

    /**
     * 为重生成流程创建封面：可解码图片生成缩略图，RAW 生成预览图。
     *
     * <p>仅供缩略图重生成任务使用；常规导入的封面由缩略图任务异步生成。</p>
     *
     * @param ownerUserId 所有者用户 ID
     * @param photo 照片实体
     * @param file 源文件描述
     * @param source 暂存源文件句柄
     * @return 封面派生文件节点 ID，无法生成时返回 null
     */
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

    private int progressPercent(int finished, int total) {
        if (total <= 0) {
            return 100;
        }
        return Math.min(100, (int) Math.round(finished * 100.0 / total));
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

    private String titleFromFileName(String fileName) {
        String name = fileName == null ? "Untitled" : fileName.trim();
        int dotIndex = name.lastIndexOf('.');
        return dotIndex <= 0 ? name : name.substring(0, dotIndex);
    }

    private PhotoScanJobDto toDto(PhotoScanJob job) {
        return new PhotoScanJobDto(
                job.getId(),
                job.getStatus(),
                job.getScannedFiles(),
                job.getMessage(),
                job.getCreatedAt(),
                job.getUpdatedAt()
        );
    }
}
