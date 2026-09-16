package com.omninest.modules.photos.service;

import com.alibaba.fastjson2.JSON;
import com.alibaba.fastjson2.TypeReference;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.messaging.QueueNames;
import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncScope;
import com.omninest.modules.file.dto.FileDownloadUrlDto;
import com.omninest.modules.file.dto.FileDescriptor;
import com.omninest.modules.file.dto.FileObjectDescriptor;
import com.omninest.modules.file.service.DerivedAssetStorageService;
import com.omninest.modules.file.dto.FileContentStream;
import com.omninest.modules.file.service.FileMetadataQueryService;
import com.omninest.modules.file.service.FileQueryService;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.photos.config.PhotoBatchDownloadProperties;
import com.omninest.modules.photos.domain.PhotoBatchTask;
import com.omninest.modules.photos.domain.PhotoItem;
import com.omninest.modules.photos.domain.PhotoTag;
import com.omninest.modules.photos.dto.PhotoDtos.CreateBatchTaskRequest;
import com.omninest.modules.photos.dto.PhotoDtos.PhotoBatchDownloadTicketDto;
import com.omninest.modules.photos.dto.PhotoDtos.PhotoBatchTaskDto;
import com.omninest.modules.photos.event.PhotoBatchEvent;
import com.omninest.modules.photos.repository.PhotoBatchTaskRepository;
import com.omninest.modules.photos.repository.PhotoItemRepository;
import com.omninest.modules.photos.repository.PhotoTagRepository;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import com.omninest.common.util.ThrowableDescriber;
import java.io.IOException;
import java.io.InputStream;
import java.nio.channels.FileChannel;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Instant;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;
import java.util.UUID;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * 照片批量处理服务，支持批量标签、移动到相册、更新拍摄时间。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class PhotoBatchService {
    private static final int COPY_BUFFER_BYTES = 64 * 1024;

    private final PhotoBatchTaskRepository batchTaskRepository;
    private final PhotoItemRepository photoItemRepository;
    private final PhotoTagRepository photoTagRepository;
    private final PhotoAlbumService albumService;
    private final TaskDispatchService taskDispatchService;
    private final FileMetadataQueryService fileMetadataQueryService;
    private final DerivedAssetStorageService derivedAssetStorageService;
    private final FileQueryService fileQueryService;
    private final TaskRecordService taskRecordService;
    private final MediaSyncEventService syncEventService;
    private final PhotoBatchDownloadProperties downloadProperties;
    private final TransactionTemplate transactionTemplate;

    /**
     * 创建批量任务并发布到 MQ 异步执行。
     */
    @Transactional(rollbackFor = Exception.class)
    public PhotoBatchTaskDto createBatchTask(UUID ownerUserId, CreateBatchTaskRequest request) {
        UUID taskId = UUID.randomUUID();
        List<UUID> photoIds = request.photoIds() == null
                ? List.of()
                : request.photoIds().stream().distinct().toList();
        Map<String, Object> taskParams = new LinkedHashMap<>();
        if (request.params() != null) {
            taskParams.putAll(request.params());
        }
        taskParams.put("photoIds", photoIds);
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("ownerUserId", ownerUserId.toString());
        payload.put("taskType", request.taskType());
        payload.put("totalItems", photoIds.size());
        payload.put("params", taskParams);
        taskRecordService.createQueuedTask(
                taskId,
                ownerUserId,
                "PHOTO_BATCH_" + request.taskType(),
                QueueNames.PHOTO_BATCH_ROUTING_KEY,
                payload);
        PhotoBatchTask task = new PhotoBatchTask();
        task.setId(taskId);
        task.setTaskId(taskId);
        task.setOwnerUserId(ownerUserId);
        task.setTaskType(request.taskType());
        task.setTotalItems(photoIds.size());
        task.setParams(JSON.toJSONString(taskParams));
        batchTaskRepository.save(task);

        PhotoBatchEvent event = new PhotoBatchEvent(task.getId(), ownerUserId);
        // 任务记录与 Outbox 投递行在同一事务提交，避免"记录已建而消息丢失"的僵尸任务。
        taskDispatchService.enqueue(
                taskId,
                QueueNames.TASK_EXCHANGE,
                QueueNames.PHOTO_BATCH_ROUTING_KEY,
                event
        );

        return toDto(task);
    }

    /**
     * 查询批量任务状态。
     */
    @Transactional(readOnly = true)
    public PhotoBatchTaskDto getTaskStatus(UUID ownerUserId, UUID taskId) {
        return batchTaskRepository.findByIdAndOwnerUserId(taskId, ownerUserId)
                .map(this::toDto)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "批量任务不存在"));
    }

    /**
     * 解析已完成批量任务的下载票据。
     *
     * @param ownerUserId 所属用户 ID
     * @param taskId 批量任务 ID
     * @return 包含签名地址、大小和摘要的下载票据
     */
    @Transactional(readOnly = true)
    public PhotoBatchDownloadTicketDto resolveDownloadTicket(UUID ownerUserId, UUID taskId) {
        PhotoBatchTask task = batchTaskRepository.findByIdAndOwnerUserId(taskId, ownerUserId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "批量任务不存在"));
        if (!"DOWNLOAD".equals(task.getTaskType()) || !"COMPLETED".equals(task.getStatus())) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "批量下载任务尚未完成");
        }
        UUID fileId = parseResultFileId(task.getResult());
        FileDescriptor fileNode = fileMetadataQueryService.findById(fileId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "批量下载文件不存在"));
        if (fileNode.currentObjectId() == null) {
            throw new BusinessException(ErrorCode.NOT_FOUND, "批量下载文件对象不存在");
        }
        FileObjectDescriptor fileObject = fileMetadataQueryService.findObjectById(fileNode.currentObjectId())
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "批量下载文件对象不存在"));
        FileDownloadUrlDto url = fileQueryService.createDownloadUrl(ownerUserId, fileId);
        return new PhotoBatchDownloadTicketDto(
                url.downloadUrl(),
                fileNode.name(),
                fileObject.sizeBytes(),
                url.expiresAt(),
                fileObject.sha256()
        );
    }

    /**
     * 执行批量任务（由 Worker 消费者调用）。
     */
    public void executeBatchTask(UUID taskId, UUID ownerUserId) {
        PhotoBatchTask task = batchTaskRepository.findById(taskId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "批量任务不存在"));
        if (!ownerUserId.equals(task.getOwnerUserId())) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "批量任务所属用户不一致");
        }
        if (!taskRecordService.claimForExecution(taskId, "PROCESSING")) {
            return;
        }

        task.setStatus("RUNNING");
        task.setErrorMessage(null);
        batchTaskRepository.save(task);

        try {
            List<UUID> photoIds = resolvePhotoIds(task);
            if ("DOWNLOAD".equals(task.getTaskType())) {
                executeDownloadTask(ownerUserId, photoIds, task);
            } else {
                executeMutationTask(ownerUserId, photoIds, task);
            }
            task.setStatus("COMPLETED");
            task.setProcessedItems(task.getTotalItems());
            batchTaskRepository.save(task);
            taskRecordService.markCompleted(taskId, Map.of(
                    "processedItems", task.getProcessedItems(),
                    "result", task.getResult() == null ? "" : task.getResult()));
        } catch (Exception ex) {
            log.error("批量任务执行失败: taskId={}", taskId, ex);
            task.setStatus("FAILED");
            task.setErrorMessage(ex.getMessage());
            batchTaskRepository.save(task);
            taskRecordService.markFailed(taskId, ex.getMessage(), ThrowableDescriber.describe(ex));
        }
    }

    private List<UUID> resolvePhotoIds(PhotoBatchTask task) {
        if (task.getParams() == null || task.getParams().isBlank()) {
            return List.of();
        }
        Map<String, Object> params = JSON.parseObject(task.getParams(), new TypeReference<>() {});
        Object ids = params.get("photoIds");
        if (ids instanceof List<?> list) {
            return list.stream()
                    .map(id -> UUID.fromString(id.toString()))
                    .distinct()
                    .toList();
        }
        return List.of();
    }

    private void executeMutationTask(UUID ownerUserId, List<UUID> photoIds, PhotoBatchTask task) {
        transactionTemplate.executeWithoutResult(status -> {
            switch (task.getTaskType()) {
                case "TAG" -> executeTagTask(ownerUserId, photoIds, task);
                case "MOVE" -> executeMoveTask(ownerUserId, photoIds, task);
                case "UPDATE_DATE" -> executeUpdateDateTask(ownerUserId, photoIds, task);
                default -> throw new BusinessException(
                        ErrorCode.BAD_REQUEST,
                        "不支持的任务类型: " + task.getTaskType()
                );
            }
        });
    }

    private void executeTagTask(UUID ownerUserId, List<UUID> photoIds, PhotoBatchTask task) {
        Map<String, Object> params = JSON.parseObject(task.getParams(), new TypeReference<>() {});
        String tag = (String) params.get("tag");
        if (tag == null || tag.isBlank()) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "标签不能为空");
        }
        // 批量查询已有标签，仅插入缺失项，减少逐条 exists+save。
        Set<UUID> existingPhotoIds = photoTagRepository
                .findByOwnerUserIdAndPhotoIdIn(ownerUserId, photoIds)
                .stream()
                .filter(pt -> tag.equals(pt.getTag()))
                .map(PhotoTag::getPhotoId)
                .collect(Collectors.toSet());
        List<PhotoTag> toInsert = photoIds.stream()
                .filter(photoId -> !existingPhotoIds.contains(photoId))
                .map(photoId -> {
                    PhotoTag photoTag = new PhotoTag();
                    photoTag.setOwnerUserId(ownerUserId);
                    photoTag.setPhotoId(photoId);
                    photoTag.setTag(tag);
                    return photoTag;
                })
                .toList();
        if (!toInsert.isEmpty()) {
            photoTagRepository.saveAll(toInsert);
            recordBatchMutationEvent(ownerUserId);
        }
    }

    private void executeMoveTask(UUID ownerUserId, List<UUID> photoIds, PhotoBatchTask task) {
        Map<String, Object> params = JSON.parseObject(task.getParams(), new TypeReference<>() {});
        String albumIdStr = (String) params.get("albumId");
        if (albumIdStr == null || albumIdStr.isBlank()) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "相册ID不能为空");
        }
        UUID albumId = UUID.fromString(albumIdStr);
        albumService.addPhotos(ownerUserId, albumId, photoIds);
    }

    private void executeUpdateDateTask(UUID ownerUserId, List<UUID> photoIds, PhotoBatchTask task) {
        Map<String, Object> params = JSON.parseObject(task.getParams(), new TypeReference<>() {});
        String dateTakenStr = (String) params.get("dateTaken");
        if (dateTakenStr == null || dateTakenStr.isBlank()) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "拍摄时间不能为空");
        }
        Instant dateTaken = Instant.parse(dateTakenStr);
        List<PhotoItem> photos = photoItemRepository.findActiveByOwnerUserIdAndIdIn(ownerUserId, photoIds);
        for (PhotoItem photo : photos) {
            photo.setDateTaken(dateTaken);
        }
        if (!photos.isEmpty()) {
            photoItemRepository.saveAll(photos);
            recordBatchMutationEvent(ownerUserId);
        }
    }

    /**
     * 批量修改落库后补发照片域失效事件，驱动各端 realtime 兜底刷新。
     *
     * <p>批量任务无单一资源实体可挂版本，事件不携带 resourceId 与版本号，
     * 客户端按 PHOTOS 作用域整体刷新。MOVE 路径经相册服务自带事件，不在此
     * 重复发布。</p>
     */
    private void recordBatchMutationEvent(UUID ownerUserId) {
        syncEventService.record(
                ownerUserId,
                SyncScope.PHOTOS,
                "PHOTO_BATCH",
                null,
                SyncAction.UPDATED,
                null,
                Map.of());
    }

    /**
     * 批量下载：将选中照片打包为 ZIP 并存储到 MinIO，结果写入 task.result。
     */
    private void executeDownloadTask(UUID ownerUserId, List<UUID> photoIds, PhotoBatchTask task) {
        if (photoIds.isEmpty()) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "照片列表不能为空");
        }
        if (photoIds.size() > downloadProperties.getMaxFiles()) {
            throw new BusinessException(ErrorCode.FILE_SIZE_EXCEEDED, "批量下载文件数量超过限制");
        }

        PhotoArchivePlan archivePlan = resolveArchiveSources(ownerUserId, photoIds);
        if (archivePlan.sources().isEmpty()) {
            throw new BusinessException(ErrorCode.NOT_FOUND, "没有可下载的照片文件");
        }

        Path zipFile = null;
        try {
            zipFile = Files.createTempFile("omninest-photo-batch-", ".zip");
            requireWorkspaceCapacity(zipFile, archivePlan.sourceBytes());
            writeArchive(zipFile, archivePlan.sources(), task);
            forceFile(zipFile);
            taskRecordService.updateProgress(task.getId(), 90);
            String zipFileName = "photos_" + task.getId() + ".zip";
            UUID zipFileId = derivedAssetStorageService.store(
                    ownerUserId,
                    "PHOTO_BATCH",
                    task.getId(),
                    "DOWNLOAD",
                    zipFileName,
                    "application/zip",
                    zipFile
            );
            task.setResult(zipFileId.toString());
        } catch (IOException exception) {
            throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "ZIP 打包失败: " + exception.getMessage());
        } finally {
            deleteTempFile(zipFile);
        }
    }

    private PhotoArchivePlan resolveArchiveSources(UUID ownerUserId, List<UUID> photoIds) {
        List<PhotoArchiveSource> sources = new ArrayList<>();
        Set<String> entryNames = new HashSet<>();
        long totalBytes = 0;
        for (UUID photoId : photoIds) {
            PhotoItem photo = photoItemRepository.findByOwnerUserIdAndId(ownerUserId, photoId).orElse(null);
            if (photo == null) {
                continue;
            }
            FileDescriptor fileNode = fileMetadataQueryService.findById(photo.getFileNodeId())
                    .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "文件节点不存在"));
            if (fileNode.currentObjectId() == null) {
                continue;
            }
            FileObjectDescriptor fileObject = fileMetadataQueryService.findObjectById(fileNode.currentObjectId())
                    .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "文件对象不存在"));
            if (fileObject.sizeBytes() < 0 || fileObject.sizeBytes() > downloadProperties.getMaxSingleFileBytes()) {
                throw new BusinessException(ErrorCode.FILE_SIZE_EXCEEDED, "批量下载单个文件大小超过限制");
            }
            try {
                totalBytes = Math.addExact(totalBytes, fileObject.sizeBytes());
            } catch (ArithmeticException exception) {
                throw new BusinessException(ErrorCode.FILE_SIZE_EXCEEDED, "批量下载文件总大小超过限制");
            }
            if (totalBytes > downloadProperties.getMaxSourceBytes()) {
                throw new BusinessException(ErrorCode.FILE_SIZE_EXCEEDED, "批量下载文件总大小超过限制");
            }
            String extension = safeExtension(photo.getFormat());
            String proposedName = String.format(
                    "%03d_%s.%s",
                    sources.size() + 1,
                    sanitizeFileName(photo.getTitle()),
                    extension
            );
            String entryName = uniqueEntryName(proposedName, entryNames);
            sources.add(new PhotoArchiveSource(
                    photo.getFileNodeId(),
                    entryName,
                    fileObject.sizeBytes(),
                    fileObject.sha256()
            ));
        }
        return new PhotoArchivePlan(List.copyOf(sources), totalBytes);
    }

    private void writeArchive(
            Path zipFile,
            List<PhotoArchiveSource> sources,
            PhotoBatchTask task
    ) throws IOException {
        try (ZipOutputStream zipOutputStream = new ZipOutputStream(Files.newOutputStream(zipFile))) {
            for (int index = 0; index < sources.size(); index++) {
                PhotoArchiveSource source = sources.get(index);
                zipOutputStream.putNextEntry(new ZipEntry(source.entryName()));
                // 内容读取统一走 File 模块接口，避免业务模块直接访问对象存储。
                try (FileContentStream contentStream = fileQueryService.openReadableFileContent(
                        task.getOwnerUserId(), source.fileNodeId())) {
                    copySource(contentStream.inputStream(), zipOutputStream, source);
                } catch (RuntimeException exception) {
                    throw new IOException("照片源读取失败: " + source.entryName(), exception);
                } finally {
                    zipOutputStream.closeEntry();
                }
                updateDownloadProgress(task, index + 1, sources.size());
            }
        }
    }

    private void copySource(
            InputStream inputStream,
            ZipOutputStream zipOutputStream,
            PhotoArchiveSource source
    ) throws IOException {
        MessageDigest digest = sha256Digest();
        byte[] buffer = new byte[COPY_BUFFER_BYTES];
        long copiedBytes = 0;
        int readBytes;
        while ((readBytes = inputStream.read(buffer)) >= 0) {
            if (readBytes == 0) {
                continue;
            }
            if (copiedBytes > source.sizeBytes() - readBytes) {
                throw new IOException("照片源大小超过元数据: " + source.entryName());
            }
            zipOutputStream.write(buffer, 0, readBytes);
            digest.update(buffer, 0, readBytes);
            copiedBytes += readBytes;
        }
        if (copiedBytes != source.sizeBytes()) {
            throw new IOException("照片源大小与元数据不一致: " + source.entryName());
        }
        if (source.sha256() != null && !source.sha256().isBlank()) {
            String actualDigest = HexFormat.of().formatHex(digest.digest());
            if (!actualDigest.equalsIgnoreCase(source.sha256())) {
                throw new IOException("照片源摘要校验失败: " + source.entryName());
            }
        }
    }

    private void updateDownloadProgress(PhotoBatchTask task, int processedItems, int totalItems) {
        int previousProgress = 10 + (int) Math.floor(70.0 * task.getProcessedItems() / totalItems);
        int progress = 10 + (int) Math.floor(70.0 * processedItems / totalItems);
        task.setProcessedItems(processedItems);
        if (processedItems < totalItems && previousProgress / 5 == progress / 5) {
            return;
        }
        batchTaskRepository.save(task);
        taskRecordService.updateProgress(task.getId(), progress);
    }

    private void requireWorkspaceCapacity(Path zipFile, long sourceBytes) throws IOException {
        long overhead = Math.max(1024L * 1024, sourceBytes / 100);
        long requiredBytes;
        try {
            requiredBytes = Math.addExact(
                    Math.addExact(sourceBytes, overhead),
                    downloadProperties.getMinFreeBytes()
            );
        } catch (ArithmeticException exception) {
            throw new BusinessException(ErrorCode.FILE_SIZE_EXCEEDED, "批量下载临时空间估算溢出");
        }
        long usableBytes = Files.getFileStore(zipFile).getUsableSpace();
        if (usableBytes < requiredBytes) {
            throw new BusinessException(ErrorCode.FILE_SIZE_EXCEEDED, "批量下载临时磁盘空间不足");
        }
    }

    private void forceFile(Path zipFile) throws IOException {
        try (FileChannel channel = FileChannel.open(zipFile, StandardOpenOption.WRITE)) {
            channel.force(true);
        }
    }

    private void deleteTempFile(Path zipFile) {
        if (zipFile == null) {
            return;
        }
        try {
            Files.deleteIfExists(zipFile);
        } catch (IOException exception) {
            log.warn("照片批量下载临时文件清理失败: errorType={}", exception.getClass().getSimpleName());
        }
    }

    private String sanitizeFileName(String name) {
        if (name == null || name.isBlank()) {
            return "photo";
        }
        String sanitized = name.replaceAll("[\\\\/:*?\"<>|]", "_").trim();
        if (sanitized.isBlank()) {
            return "photo";
        }
        return sanitized.length() > 120 ? sanitized.substring(0, 120) : sanitized;
    }

    private String safeExtension(String format) {
        if (format == null || format.isBlank()) {
            return "jpg";
        }
        String sanitized = format.replaceAll("[^A-Za-z0-9]", "").toLowerCase();
        if (sanitized.isBlank() || sanitized.length() > 10) {
            return "jpg";
        }
        return sanitized;
    }

    private String uniqueEntryName(String proposedName, Set<String> entryNames) {
        if (entryNames.add(proposedName)) {
            return proposedName;
        }
        int extensionOffset = proposedName.lastIndexOf('.');
        String baseName = extensionOffset > 0 ? proposedName.substring(0, extensionOffset) : proposedName;
        String extension = extensionOffset > 0 ? proposedName.substring(extensionOffset) : "";
        int suffix = 2;
        String candidate;
        do {
            candidate = baseName + "_" + suffix + extension;
            suffix++;
        } while (!entryNames.add(candidate));
        return candidate;
    }

    private UUID parseResultFileId(String result) {
        if (result == null || result.isBlank()) {
            throw new BusinessException(ErrorCode.NOT_FOUND, "批量下载结果不存在");
        }
        try {
            return UUID.fromString(result);
        } catch (IllegalArgumentException exception) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "批量下载结果格式不正确");
        }
    }

    private MessageDigest sha256Digest() {
        try {
            return MessageDigest.getInstance("SHA-256");
        } catch (NoSuchAlgorithmException exception) {
            throw new IllegalStateException("运行环境不支持 SHA-256", exception);
        }
    }

    private record PhotoArchivePlan(List<PhotoArchiveSource> sources, long sourceBytes) {
    }

    private record PhotoArchiveSource(
            UUID fileNodeId,
            String entryName,
            long sizeBytes,
            String sha256
    ) {
    }

    private PhotoBatchTaskDto toDto(PhotoBatchTask task) {
        return new PhotoBatchTaskDto(
                task.getId(),
                task.getTaskType(),
                task.getStatus(),
                task.getTotalItems(),
                task.getProcessedItems(),
                task.getResult(),
                task.getErrorMessage(),
                task.getCreatedAt()
        );
    }
}
