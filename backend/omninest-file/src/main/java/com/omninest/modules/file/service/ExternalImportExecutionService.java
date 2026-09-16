package com.omninest.modules.file.service;

import com.omninest.common.error.BusinessException;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.messaging.DomainEventPublisher;
import com.omninest.common.messaging.QueueNames;
import com.omninest.common.rclone.RcloneGateway;
import com.omninest.common.storage.LocalExternalStorageSettings;
import com.omninest.common.storage.ObjectStorageBuckets;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.modules.file.domain.ImportTaskStatus;
import com.omninest.modules.file.domain.NodeType;
import com.omninest.modules.file.domain.SourceType;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.common.storage.ObjectStorageCompletedPart;
import com.omninest.common.storage.ObjectStorageKey;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.FileObject;
import com.omninest.modules.file.domain.ImportSourceKind;
import com.omninest.modules.file.domain.StorageExternalAccount;
import com.omninest.modules.file.domain.StorageImportTask;
import com.omninest.modules.file.event.ExternalImportRequestedEvent;
import com.omninest.modules.file.event.FileUploadedEvent;
import com.omninest.modules.file.service.FileIngressSafetyService.InspectionResult;
import com.omninest.modules.file.service.FileIngressLifecycleService.IngressCommand;
import com.omninest.modules.file.repository.FileNodeRepository;
import com.omninest.modules.file.repository.FileObjectRepository;
import com.omninest.modules.file.repository.StorageExternalAccountRepository;
import com.omninest.modules.file.repository.StorageImportTaskRepository;
import com.omninest.modules.notification.port.NotificationPublisher;
import com.omninest.modules.quota.service.StorageQuotaService;
import com.omninest.modules.task.service.TaskRecordService;
import com.omninest.common.util.ThrowableDescriber;
import java.io.IOException;
import java.io.InputStream;
import java.io.RandomAccessFile;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.Path;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.atomic.AtomicReference;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * 外部存储导入执行服务。
 * <p>
 * 负责从外部存储（rclone remote）下载文件到本地临时目录，
 * 然后上传到 MinIO 并创建 FileNode/FileObject 业务记录。
 * <p>
 * 复用离线下载的导入模式：rclone sync/copy → 轮询进度 → 上传 MinIO → 创建文件树。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class ExternalImportExecutionService {
    private final StorageImportTaskRepository importTaskRepository;
    private final StorageExternalAccountRepository accountRepository;
    private final FileNodeRepository fileNodeRepository;
    private final FileObjectRepository fileObjectRepository;
    private final StorageQuotaService storageQuotaService;
    private final SharedSpaceQuotaService sharedSpaceQuotaService;
    private final ObjectStorageClient objectStorageClient;
    private final DomainEventPublisher domainEventPublisher;
    private final FilePostProcessingTaskService postProcessingTaskService;
    private final RcloneGateway rcloneGateway;
    private final LocalExternalStorageSettings localStorageSettings;
    private final ExternalStorageService externalStorageService;
    private final ObjectStorageBuckets objectStorageBuckets;
    private final TransactionTemplate transactionTemplate;
    private final NotificationPublisher notificationService;
    private final TaskRecordService taskRecordService;
    private final BoundedFileTreeScanner fileTreeScanner;
    private final FileIngressSafetyService ingressSafetyService;
    private final FileIngressLifecycleService ingressLifecycleService;

    private static final int POLL_INTERVAL_SECONDS = 2;
    private static final int MAX_RCLONE_RETRIES = 3;
    private static final long RCLONE_IDLE_TIMEOUT_MINUTES = 30;

    /** 大于此阈值的文件使用 multipart 并行上传。 */
    private static final long MULTIPART_THRESHOLD_BYTES = 64L * 1024 * 1024;
    /** 每个分片大小：32MB。 */
    private static final long PART_SIZE_BYTES = 32L * 1024 * 1024;
    /** 并行上传分片数。 */
    private static final int MULTIPART_CONCURRENCY = 4;

    /**
     * 执行外部存储导入任务。
     * <p>
     * LOCAL provider 直接从宿主机路径读取文件上传到 MinIO，绕过 rclone。
     * 其他 provider 使用 rclone sync/copy 下载到临时目录后再上传。
     *
     * @param event 外部存储导入请求事件
     */
    public void execute(ExternalImportRequestedEvent event) {
        try {
            StorageImportTask task = markRunning(event.taskId());
            if (task == null) {
                log.warn("导入任务未能进入执行态: taskId={}", event.taskId());
                return;
            }

            StorageExternalAccount account = accountRepository.findById(task.getExternalAccountId())
                    .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "外部存储账户不存在"));

            if ("LOCAL".equalsIgnoreCase(account.getProvider())) {
                markFailed(task.getId(), "本地目录导入已停用，请使用存储位置或上传");
                return;
            }
            executeRcloneImport(task, account);
        } finally {
            progressThrottle.remove(event.taskId());
        }
    }

    private FileNode importSingleFile(
            StorageImportTask task,
            UUID destinationParentId,
            String fileName,
            Path file,
            long totalSize,
            long baseTransferred
    ) {
        if (isCancelled(task.getId())) {
            return null;
        }

        String quarantineBucket = objectStorageBuckets.quarantine();
        String targetBucket = objectStorageBuckets.userFiles();
        String mimeType = detectMimeType(file);
        long size = fileSize(file);
        externalStorageService.ensureSingleFileAllowed(size);

        // 事务内：准备 objectKey 和 availableName
        var prepResult = transactionTemplate.execute(status -> {
            StorageImportTask t = requireTask(task.getId());
            if (ImportTaskStatus.CANCELLED.getValue().equals(t.getStatus())) {
                return null;
            }

            FileNode targetParent = resolveParent(t, destinationParentId);
            SpaceType spaceType = resolveSpaceType(t);
            String availableName = resolveAvailableName(
                    t,
                    targetParent == null ? null : targetParent.getId(),
                    fileName
            );

            String quarantineObjectKey = "external-imports/" + t.getOwnerUserId() + "/" + task.getId()
                    + "/" + UUID.randomUUID() + "/" + availableName;
            String targetObjectKey = "users/" + t.getOwnerUserId() + "/imports/" + task.getId()
                    + "/" + UUID.randomUUID() + "/" + availableName;

            return new ImportPrep(
                    targetParent,
                    availableName,
                    quarantineObjectKey,
                    targetObjectKey,
                    spaceType
            );
        });

        if (prepResult == null) {
            return null;
        }

        // 事务外：上传到 MinIO，大文件走 multipart 并行上传
        ObjectStorageKey quarantineKey = new ObjectStorageKey(
                quarantineBucket,
                prepResult.quarantineObjectKey
        );
        if (size > MULTIPART_THRESHOLD_BYTES) {
            multipartUpload(task.getId(), quarantineKey, file, size, mimeType, baseTransferred);
        } else {
            try (InputStream raw = Files.newInputStream(file)) {
                InputStream progressStream = ExternalImportStreams.tracking(raw, bytesRead -> {
                    long current = baseTransferred + bytesRead;
                    updateTransferredBytes(task.getId(), current);
                });
                objectStorageClient.putObject(quarantineKey, progressStream, size, mimeType);
            } catch (IOException e) {
                throw new IllegalStateException("读取文件失败: " + file, e);
            }
        }

        ObjectStorageKey targetKey = new ObjectStorageKey(targetBucket, prepResult.targetObjectKey);
        UUID ingressId = ingressLifecycleService.open(new IngressCommand(
                task.getOwnerUserId(),
                "EXTERNAL",
                task.getId(),
                null,
                quarantineKey.bucket(),
                quarantineKey.objectKey(),
                targetKey.bucket(),
                targetKey.objectKey(),
                destinationParentId,
                prepResult.availableName,
                size,
                mimeType
        ));
        ingressLifecycleService.markScanning(ingressId);
        InspectionResult inspection;
        try {
            inspection = ingressSafetyService.inspect(
                    quarantineKey,
                    size,
                    "EXTERNAL",
                    task.getId()
            );
        } catch (BusinessException exception) {
            ingressLifecycleService.markFailed(
                    ingressId,
                    exception.errorCode() == ErrorCode.FILE_SECURITY_REJECTED,
                    exception.errorCode().name(),
                    exception.getMessage()
            );
            throw exception;
        }
        ingressLifecycleService.markClean(ingressId, inspection.sha256());
        objectStorageClient.copyObject(quarantineKey, targetKey);

        // 事务内：创建 FileObject、FileNode
        try {
            FileNode savedNode = transactionTemplate.execute(status -> {
                StorageImportTask t = requireTask(task.getId());
                if (ImportTaskStatus.CANCELLED.getValue().equals(t.getStatus())) {
                    return null;
                }

                FileObject fileObject = new FileObject();
                fileObject.setBucketName(targetBucket);
                fileObject.setObjectKey(prepResult.targetObjectKey);
                fileObject.setSha256(inspection.sha256());
                fileObject.setSizeBytes(size);
                fileObject.setMimeType(mimeType);
                FileObject savedObject = fileObjectRepository.save(fileObject);

                FileNode fileNode = new FileNode();
                fileNode.setOwnerUserId(t.getOwnerUserId());
                fileNode.setParentId(prepResult.targetParent == null ? null : prepResult.targetParent.getId());
                fileNode.setNodeType(NodeType.FILE.getValue());
                fileNode.setName(prepResult.availableName);
                fileNode.setNormalizedPath(resolveChildPath(prepResult.targetParent, prepResult.availableName));
                fileNode.setMimeType(mimeType);
                fileNode.setSizeBytes(savedObject.getSizeBytes());
                fileNode.setCurrentObjectId(savedObject.getId());
                fileNode.setSourceType(SourceType.RCLONE.getValue());
                fileNode.setSpaceType(prepResult.spaceType);
                if (prepResult.spaceType == SpaceType.SHARED) {
                    fileNode.setUploadedBy(t.getOwnerUserId());
                }
                FileNode persistedNode = fileNodeRepository.save(fileNode);

                publishFileUploaded(persistedNode, savedObject);
                return persistedNode;
            });
            removeObjectQuietly(quarantineKey);
            if (savedNode == null) {
                ingressLifecycleService.markFailed(
                        ingressId,
                        false,
                        ErrorCode.FILE_UPLOAD_FAILED.name(),
                        "外部导入在发布前被取消"
                );
                removeObjectQuietly(targetKey);
            } else {
                ingressLifecycleService.markAvailable(ingressId, savedNode.getId());
            }
            return savedNode;
        } catch (RuntimeException exception) {
            ingressLifecycleService.markFailed(
                    ingressId,
                    false,
                    ErrorCode.FILE_UPLOAD_FAILED.name(),
                    summarize(exception)
            );
            removeObjectQuietly(targetKey);
            throw exception;
        }
    }

    /**
     * 更新已传输字节和速率（节流：每秒最多写一次数据库）。
     */
    private void updateTransferredBytes(UUID taskId, long bytes) {
        long now = System.currentTimeMillis();
        ProgressSnapshot last = progressThrottle.get(taskId);
        if (last != null && now - last.timestampMs() < 1000) {
            return;
        }

        long speed = 0;
        if (last != null) {
            long elapsed = now - last.timestampMs();
            if (elapsed > 0) {
                speed = (bytes - last.bytes()) * 1000L / elapsed;
            }
        }
        progressThrottle.put(taskId, new ProgressSnapshot(bytes, now));

        final long finalSpeed = speed;
        try {
            transactionTemplate.executeWithoutResult(status -> {
                StorageImportTask t = importTaskRepository.findById(taskId).orElse(null);
                if (t == null || ImportTaskStatus.CANCELLED.getValue().equals(t.getStatus())) {
                    return;
                }
                t.setTransferredBytes(bytes);
                t.setSpeedBytes(finalSpeed);
                importTaskRepository.save(t);
                taskRecordService.updateProgress(systemTaskId(t), progressFromBytes(t.getTotalBytes(), bytes));
            });
        } catch (Exception e) {
            log.debug("更新进度失败: taskId={}", taskId, e);
        }
    }

    /** 进度快照：用于计算传输速率。 */
    private record ProgressSnapshot(long bytes, long timestampMs) {}

    /** 进度节流：避免频繁写库。 */
    private final ConcurrentHashMap<UUID, ProgressSnapshot> progressThrottle =
            new ConcurrentHashMap<>();

    private record ImportPrep(
            FileNode targetParent,
            String availableName,
            String quarantineObjectKey,
            String targetObjectKey,
            SpaceType spaceType
    ) {
    }

    private void removeObjectQuietly(ObjectStorageKey key) {
        try {
            objectStorageClient.removeObject(key);
        } catch (RuntimeException exception) {
            log.warn("清理外部导入临时对象失败: bucket={}, errorType={}",
                    key.bucket(), exception.getClass().getSimpleName());
        }
    }

    /**
     * 使用 S3 multipart 并行上传大文件。
     * <p>
     * 将文件分为多个 32MB 分片，使用 4 个虚拟线程并行上传，
     * 每个分片的进度通过回调汇总到任务进度。
     */
    private void multipartUpload(
            UUID taskId, ObjectStorageKey key, Path file,
            long size, String mimeType, long baseTransferred
    ) {
        List<PartRange> parts = calculateParts(size);
        String uploadId = objectStorageClient.initiateMultipartUpload(key, mimeType);

        AtomicLong partBytesRead = new AtomicLong(0);
        AtomicReference<Throwable> error = new AtomicReference<>();
        CountDownLatch latch = new CountDownLatch(parts.size());

        ExecutorService executor = Executors.newFixedThreadPool(
                Math.min(MULTIPART_CONCURRENCY, parts.size()),
                Thread.ofVirtual().factory()
        );

        try {
            List<ObjectStorageCompletedPart> completedParts = new ArrayList<>();
            for (PartRange part : parts) {
                executor.submit(() -> {
                    if (error.get() != null || isCancelled(taskId)) {
                        latch.countDown();
                        return;
                    }
                    try (RandomAccessFile raf = new RandomAccessFile(file.toFile(), "r")) {
                        raf.seek(part.offset());
                        InputStream partStream = ExternalImportStreams.bounded(
                                raf, part.length(), bytesRead -> {
                            long total = baseTransferred + partBytesRead.get() + bytesRead;
                            updateTransferredBytes(taskId, total);
                        });
                        ObjectStorageCompletedPart completed =
                                objectStorageClient.uploadPart(
                                        key,
                                        uploadId,
                                        part.partNumber(),
                                        partStream,
                                        part.length()
                                );
                        synchronized (completedParts) {
                            completedParts.add(completed);
                        }
                        partBytesRead.addAndGet(part.length());
                    } catch (Throwable t) {
                        error.compareAndSet(null, t);
                    } finally {
                        latch.countDown();
                    }
                });
            }

            latch.await();

            if (error.get() != null) {
                objectStorageClient.abortMultipartUpload(key, uploadId);
                throw new IllegalStateException("分片上传失败", error.get());
            }
            if (isCancelled(taskId)) {
                objectStorageClient.abortMultipartUpload(key, uploadId);
                return;
            }

            completedParts.sort(Comparator.comparingInt(ObjectStorageCompletedPart::partNumber));
            objectStorageClient.completeMultipartUpload(key, uploadId, completedParts);
        } catch (InterruptedException e) {
            objectStorageClient.abortMultipartUpload(key, uploadId);
            Thread.currentThread().interrupt();
            throw new IllegalStateException("分片上传被中断", e);
        } finally {
            executor.shutdown();
        }
    }

    /** 计算文件分片信息。 */
    private List<PartRange> calculateParts(long fileSize) {
        List<PartRange> parts = new ArrayList<>();
        int partNumber = 1;
        long offset = 0;
        while (offset < fileSize) {
            long length = Math.min(PART_SIZE_BYTES, fileSize - offset);
            parts.add(new PartRange(partNumber++, offset, length));
            offset += length;
        }
        return parts;
    }

    private record PartRange(int partNumber, long offset, long length) {}

    /**
     * 非 LOCAL provider：通过 rclone sync/copy 下载到临时目录再导入。
     */
    private void executeRcloneImport(StorageImportTask task, StorageExternalAccount account) {
        Path tempDir = Path.of(localStorageSettings.importHostRoot(), task.getId().toString())
                .toAbsolutePath().normalize();

        try {
            Files.createDirectories(tempDir);
            externalStorageService.activateRemote(account);

            String sourceFs = externalStorageService.resolveFs(account);
            String sourcePath = normalizeRclonePath(task.getSourcePath());
            String dstFs = "local:" + resolveContainerImportPath(task.getId());
            String group = "import-" + task.getId();
            markTransferring(task.getId());
            int rcloneJobId;
            if (isDirectoryTask(task)) {
                String directoryFs = sourcePath.isEmpty()
                        ? sourceFs
                        : sourceFs.endsWith("/") ? sourceFs + sourcePath : sourceFs + "/" + sourcePath;
                rcloneJobId = rcloneGateway.startDirectoryCopy(directoryFs, dstFs, group);
            } else {
                rcloneJobId = rcloneGateway.startFileCopy(
                        sourceFs,
                        sourcePath,
                        dstFs,
                        task.getFileName(),
                        group
                );
            }
            updateRcloneJobId(task.getId(), rcloneJobId);

            log.info("Rclone 导入已启动: taskId={}, jobId={}, sourceKind={}, src={} → dst={}",
                    task.getId(), rcloneJobId, task.getSourceKind(), task.getSourcePath(), dstFs);

            // 轮询等待完成
            boolean completed = waitForCompletion(task.getId(), rcloneJobId, group);
            if (!completed) {
                return;
            }

            importCompletedFiles(task.getId(), tempDir);

        } catch (Exception e) {
            log.warn("外部存储导入失败: taskId={}, message={}", task.getId(), e.getMessage());
            markFailed(task.getId(), summarize(e), ThrowableDescriber.describe(e));
        } finally {
            cleanupTempDir(tempDir);
        }
    }

    private StorageImportTask markRunning(UUID taskId) {
        return transactionTemplate.execute(status ->
                importTaskRepository.findById(taskId)
                        .filter(t -> ImportTaskStatus.QUEUED.getValue().equals(t.getStatus()))
                        .map(t -> {
                            if (!taskRecordService.claimForExecution(systemTaskId(t), "SCANNING")) {
                                return null;
                            }
                            t.setStatus(ImportTaskStatus.SCANNING.getValue());
                            t.setErrorSummary(null);
                            return importTaskRepository.save(t);
                        })
                        .orElse(null)
        );
    }

    private void markTransferring(UUID taskId) {
        transactionTemplate.executeWithoutResult(status -> {
            StorageImportTask task = requireTask(taskId);
            task.setStatus(ImportTaskStatus.TRANSFERRING.getValue());
            task.setCurrentFileName(task.getSourcePath());
            importTaskRepository.save(task);
        });
    }

    private void updateRcloneJobId(UUID taskId, int rcloneJobId) {
        transactionTemplate.executeWithoutResult(status -> {
            StorageImportTask task = requireTask(taskId);
            task.setRcloneJobId(rcloneJobId);
            task.setRcloneGroup("import-" + taskId);
            importTaskRepository.save(task);
        });
    }

    /**
     * 轮询 rclone job 状态和传输进度。
     */
    private boolean waitForCompletion(UUID taskId, int rcloneJobId, String group) {
        int consecutiveFailures = 0;
        Instant startedAt = Instant.now();
        while (true) {
            // 检查是否被取消
            if (isCancelled(taskId)) {
                try {
                    rcloneGateway.stopJob(rcloneJobId);
                } catch (Exception e) {
                    log.warn("停止 rclone job 失败: jobId={}", rcloneJobId, e);
                }
                markCancelled(taskId);
                return false;
            }
            // 总超时兜底：避免 rclone 一直 active 且无成功/取消时消费线程永久占用。
            if (Duration.between(startedAt, Instant.now()).toMinutes() >= RCLONE_IDLE_TIMEOUT_MINUTES) {
                markFailed(taskId, "外部导入长时间未完成，已超时中止");
                return false;
            }

            try {
                RcloneGateway.JobStatus jobStatus = rcloneGateway.queryJobStatus(rcloneJobId);

                // 获取传输统计
                updateProgressFromStats(taskId, group);

                if (jobStatus.finished()) {
                    if (jobStatus.successful()) {
                        return true;
                    }
                    String error = jobStatus.error();
                    markFailed(taskId, error != null && !error.isBlank() ? error : "Rclone 传输失败");
                    return false;
                }

                consecutiveFailures = 0;
            } catch (Exception e) {
                consecutiveFailures++;
                log.warn("Rclone 状态查询失败 ({}): taskId={}, jobId={}", consecutiveFailures, taskId, rcloneJobId, e);
                if (consecutiveFailures >= MAX_RCLONE_RETRIES) {
                    markFailed(taskId, "Rclone 连接失败，已重试 " + MAX_RCLONE_RETRIES + " 次");
                    return false;
                }
            }

            sleep(POLL_INTERVAL_SECONDS);
        }
    }

    /**
     * 从 rclone core/stats 获取传输进度并更新任务。
     */
    private void updateProgressFromStats(UUID taskId, String group) {
        try {
            RcloneGateway.TransferStats stats = rcloneGateway.queryTransferStats(group);
            long totalBytes = stats.totalBytes();
            long transferredBytes = stats.transferredBytes();
            long speed = stats.speedBytes();

            transactionTemplate.executeWithoutResult(status -> {
                StorageImportTask task = requireTask(taskId);
                if (ImportTaskStatus.CANCELLED.getValue().equals(task.getStatus())) {
                    return;
                }
                task.setTotalBytes(totalBytes);
                task.setTransferredBytes(transferredBytes);
                task.setSpeedBytes(speed);
                importTaskRepository.save(task);
                taskRecordService.updateProgress(systemTaskId(task), progressFromBytes(totalBytes, transferredBytes));
            });
        } catch (Exception e) {
            log.debug("获取 rclone 传输统计失败: taskId={}", taskId, e);
        }
    }

    /**
     * 扫描临时目录中的文件，上传到 MinIO 并创建 FileNode/FileObject 记录。
     */
    private void importCompletedFiles(UUID taskId, Path tempDir) {
        List<Path> files;
        try {
            files = fileTreeScanner.listRegularFiles(tempDir);
        } catch (IOException e) {
            throw new IllegalStateException("读取导入结果失败", e);
        }

        if (files.isEmpty()) {
            markFailed(taskId, "Rclone 未生成可导入文件");
            return;
        }

        StorageImportTask task = requireTask(taskId);
        long totalSize = files.stream().mapToLong(this::fileSize).sum();
        prepareImportPhase(taskId, totalSize, files.size());

        UUID importRootId = isDirectoryTask(task) ? createImportRoot(task) : task.getTargetParentId();
        Map<String, UUID> folderCache = new HashMap<>();
        FileNode lastImported = null;
        long transferred = 0L;
        int completedFiles = 0;
        for (Path file : files) {
            if (isCancelled(taskId)) {
                markCancelled(taskId);
                return;
            }
            Path relative = tempDir.relativize(file).normalize();
            UUID destinationParentId = isDirectoryTask(task)
                    ? ensureRelativeFolders(task, importRootId, relative.getParent(), folderCache)
                    : importRootId;
            updateCurrentFile(taskId, relative.toString(), completedFiles);
            lastImported = importSingleFile(
                    task,
                    destinationParentId,
                    file.getFileName().toString(),
                    file,
                    totalSize,
                    transferred
            );
            transferred += fileSize(file);
            completedFiles++;
            updateCompletedFile(taskId, relative.toString(), transferred, completedFiles);
        }

        UUID completedNodeId = isDirectoryTask(task)
                ? importRootId
                : lastImported == null ? null : lastImported.getId();
        markCompleted(taskId, completedNodeId, totalSize, files.size());
        log.info("外部存储导入完成: taskId={}, files={}, totalBytes={}", taskId, files.size(), totalSize);
        // 发送完成通知
        StorageImportTask completedTask = importTaskRepository.findById(taskId).orElse(null);
        if (completedTask != null) {
            notificationService.notifyOrLog(completedTask.getOwnerUserId(), "TASK_COMPLETED",
                    "文件导入完成", "外部存储导入已完成",
                    Map.of("taskId", taskId.toString()));
        }
    }

    private void prepareImportPhase(UUID taskId, long totalSize, int totalFiles) {
        transactionTemplate.executeWithoutResult(status -> {
            StorageImportTask task = requireTask(taskId);
            if (ImportTaskStatus.CANCELLED.getValue().equals(task.getStatus())) {
                return;
            }
            if (SpaceType.SHARED == resolveSpaceType(task)) {
                sharedSpaceQuotaService.checkQuota(totalSize);
            } else {
                storageQuotaService.reserve(
                        task.getOwnerUserId(),
                        "EXTERNAL_IMPORT",
                        task.getId(),
                        totalSize,
                        Instant.now().plus(Duration.ofHours(24))
                );
            }
            externalStorageService.ensureImportBytesAllowed(totalSize);
            resolveParent(task, task.getTargetParentId());
            task.setStatus(ImportTaskStatus.IMPORTING.getValue());
            task.setTotalBytes(totalSize);
            task.setTransferredBytes(0L);
            task.setSpeedBytes(0L);
            task.setTotalFiles(totalFiles);
            task.setCompletedFiles(0);
            task.setCurrentFileName(null);
            importTaskRepository.save(task);
            taskRecordService.updateProgress(systemTaskId(task), 10);
        });
    }

    private UUID createImportRoot(StorageImportTask task) {
        return transactionTemplate.execute(status -> {
            StorageImportTask currentTask = requireTask(task.getId());
            FileNode targetParent = resolveParent(currentTask, currentTask.getTargetParentId());
            SpaceType spaceType = resolveSpaceType(currentTask);
            String availableName = resolveAvailableName(
                    currentTask,
                    targetParent == null ? null : targetParent.getId(),
                    currentTask.getFileName()
            );
            FileNode folder = new FileNode();
            folder.setOwnerUserId(currentTask.getOwnerUserId());
            folder.setParentId(targetParent == null ? null : targetParent.getId());
            folder.setNodeType(NodeType.FOLDER.getValue());
            folder.setName(availableName);
            folder.setNormalizedPath(resolveChildPath(targetParent, availableName));
            folder.setSizeBytes(0L);
            folder.setSourceType(SourceType.RCLONE.getValue());
            folder.setSpaceType(spaceType);
            if (spaceType == SpaceType.SHARED) {
                folder.setUploadedBy(currentTask.getOwnerUserId());
            }
            return fileNodeRepository.save(folder).getId();
        });
    }

    private UUID ensureRelativeFolders(
            StorageImportTask task,
            UUID rootFolderId,
            Path relativeParent,
            Map<String, UUID> folderCache
    ) {
        if (relativeParent == null || relativeParent.getNameCount() == 0) {
            return rootFolderId;
        }
        UUID parentId = rootFolderId;
        StringBuilder cacheKey = new StringBuilder();
        for (Path segment : relativeParent) {
            if (!cacheKey.isEmpty()) {
                cacheKey.append('/');
            }
            cacheKey.append(segment);
            String key = cacheKey.toString();
            UUID cached = folderCache.get(key);
            if (cached != null) {
                parentId = cached;
                continue;
            }
            parentId = createChildFolder(task, parentId, segment.toString());
            folderCache.put(key, parentId);
        }
        return parentId;
    }

    private UUID createChildFolder(StorageImportTask task, UUID parentId, String folderName) {
        return transactionTemplate.execute(status -> {
            StorageImportTask currentTask = requireTask(task.getId());
            FileNode parent = resolveParent(currentTask, parentId);
            SpaceType spaceType = resolveSpaceType(currentTask);
            String availableName = resolveAvailableName(currentTask, parentId, folderName);
            FileNode folder = new FileNode();
            folder.setOwnerUserId(currentTask.getOwnerUserId());
            folder.setParentId(parentId);
            folder.setNodeType(NodeType.FOLDER.getValue());
            folder.setName(availableName);
            folder.setNormalizedPath(resolveChildPath(parent, availableName));
            folder.setSizeBytes(0L);
            folder.setSourceType(SourceType.RCLONE.getValue());
            folder.setSpaceType(spaceType);
            if (spaceType == SpaceType.SHARED) {
                folder.setUploadedBy(currentTask.getOwnerUserId());
            }
            return fileNodeRepository.save(folder).getId();
        });
    }

    private void updateCurrentFile(UUID taskId, String currentFileName, int completedFiles) {
        transactionTemplate.executeWithoutResult(status -> {
            StorageImportTask task = requireTask(taskId);
            task.setCurrentFileName(currentFileName);
            task.setCompletedFiles(completedFiles);
            importTaskRepository.save(task);
        });
    }

    private void updateCompletedFile(
            UUID taskId,
            String currentFileName,
            long transferredBytes,
            int completedFiles
    ) {
        transactionTemplate.executeWithoutResult(status -> {
            StorageImportTask task = requireTask(taskId);
            task.setCurrentFileName(currentFileName);
            task.setTransferredBytes(transferredBytes);
            task.setCompletedFiles(completedFiles);
            importTaskRepository.save(task);
            int progress = task.getTotalFiles() <= 0
                    ? progressFromBytes(task.getTotalBytes(), transferredBytes)
                    : Math.max(10, Math.min(99, completedFiles * 100 / task.getTotalFiles()));
            taskRecordService.updateProgress(systemTaskId(task), progress);
        });
    }

    private void markCompleted(UUID taskId, UUID completedNodeId, long totalSize, int fileCount) {
        transactionTemplate.executeWithoutResult(status -> {
            StorageImportTask task = requireTask(taskId);
            if (ImportTaskStatus.CANCELLED.getValue().equals(task.getStatus())) {
                return;
            }
            if (SpaceType.SHARED == resolveSpaceType(task)) {
                sharedSpaceQuotaService.increaseUsage(totalSize);
            } else {
                storageQuotaService.settleReservation("EXTERNAL_IMPORT", task.getId(), totalSize);
            }
            task.setStatus(ImportTaskStatus.COMPLETED.getValue());
            task.setTransferredBytes(totalSize);
            task.setSpeedBytes(0L);
            task.setCompletedFiles(fileCount);
            task.setCurrentFileName(null);
            task.setCompletedFileId(completedNodeId);
            importTaskRepository.save(task);
            taskRecordService.markCompleted(systemTaskId(task), Map.of(
                    "completedFileId", completedNodeId == null ? "" : completedNodeId.toString(),
                    "totalBytes", totalSize,
                    "fileCount", fileCount
            ));
        });
    }

    private boolean isDirectoryTask(StorageImportTask task) {
        return ImportSourceKind.DIRECTORY == ImportSourceKind.fromValue(task.getSourceKind());
    }

    private String normalizeRclonePath(String sourcePath) {
        if (sourcePath == null || sourcePath.isBlank() || "/".equals(sourcePath)) {
            return "";
        }
        String normalized = sourcePath.startsWith("/") ? sourcePath.substring(1) : sourcePath;
        return normalized.endsWith("/") ? normalized.substring(0, normalized.length() - 1) : normalized;
    }

    private String resolveContainerImportPath(UUID taskId) {
        String root = localStorageSettings.importContainerRoot().replace('\\', '/');
        String normalizedRoot = root.endsWith("/") ? root.substring(0, root.length() - 1) : root;
        return normalizedRoot + "/" + taskId;
    }

    private void publishFileUploaded(FileNode fileNode, FileObject object) {
        FileUploadedEvent event = new FileUploadedEvent(
                fileNode.getId(),
                object.getId(),
                fileNode.getOwnerUserId(),
                object.getBucketName(),
                object.getObjectKey(),
                fileNode.getName(),
                fileNode.getMimeType(),
                fileNode.getSizeBytes(),
                Instant.now()
        );
        postProcessingTaskService.enqueueMediaAutoImport(event);
        domainEventPublisher.publishTask(QueueNames.FILE_INDEX_ROUTING_KEY, event);
    }

    // ========== 辅助方法 ==========

    private boolean isCancelled(UUID taskId) {
        return Boolean.TRUE.equals(transactionTemplate.execute(status ->
                importTaskRepository.findById(taskId)
                        .map(task -> ImportTaskStatus.CANCELLED.getValue().equals(task.getStatus()))
                        .orElse(true)
        ));
    }

    private void markCancelled(UUID taskId) {
        transactionTemplate.executeWithoutResult(status -> {
            StorageImportTask task = requireTask(taskId);
            storageQuotaService.settleReservation(
                    "EXTERNAL_IMPORT",
                    task.getId(),
                    task.getTransferredBytes()
            );
            task.setStatus(ImportTaskStatus.CANCELLED.getValue());
            task.setSpeedBytes(0L);
            importTaskRepository.save(task);
            taskRecordService.markCancelled(systemTaskId(task));
        });
    }

    private void markFailed(UUID taskId, String errorSummary) {
        markFailed(taskId, errorSummary, null);
    }

    private void markFailed(UUID taskId, String errorSummary, String stackSummary) {
        transactionTemplate.executeWithoutResult(status -> {
            StorageImportTask task = requireTask(taskId);
            if (ImportTaskStatus.CANCELLED.getValue().equals(task.getStatus())) {
                return;
            }
            storageQuotaService.settleReservation(
                    "EXTERNAL_IMPORT",
                    task.getId(),
                    task.getTransferredBytes()
            );
            task.setStatus(ImportTaskStatus.FAILED.getValue());
            task.setSpeedBytes(0L);
            task.setErrorSummary(errorSummary);
            importTaskRepository.save(task);
            taskRecordService.markFailed(systemTaskId(task), errorSummary, stackSummary);
        });
        // 发送失败通知
        StorageImportTask failedTask = importTaskRepository.findById(taskId).orElse(null);
        if (failedTask != null) {
            notificationService.notifyOrLog(failedTask.getOwnerUserId(), "TASK_FAILED",
                    "文件导入失败", "导入失败: " + errorSummary,
                    Map.of("taskId", taskId.toString()));
        }
    }

    private StorageImportTask requireTask(UUID taskId) {
        return importTaskRepository.findById(taskId)
                .orElseThrow(() -> new BusinessException(ErrorCode.TASK_NOT_FOUND, "导入任务不存在"));
    }

    private UUID systemTaskId(StorageImportTask task) {
        return task.getTaskId() == null ? task.getId() : task.getTaskId();
    }

    private int progressFromBytes(long totalBytes, long transferredBytes) {
        if (totalBytes <= 0L) {
            return 10;
        }
        long progress = transferredBytes * 100L / totalBytes;
        return (int) Math.max(10L, Math.min(99L, progress));
    }

    private FileNode resolveParent(StorageImportTask task, UUID parentId) {
        if (parentId == null) {
            return null;
        }
        if (resolveSpaceType(task) == SpaceType.SHARED) {
            return fileNodeRepository.findByIdAndSpaceTypeAndDeletedFalse(parentId, SpaceType.SHARED)
                    .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "共享空间父级文件夹不存在"));
        }
        return fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(parentId, task.getOwnerUserId())
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "父级文件夹不存在"));
    }

    private static final int MAX_NAME_COLLISION_ITERATIONS = 1000;

    private String resolveAvailableName(StorageImportTask task, UUID parentId, String requestedName) {
        String name = requestedName;
        int dotIndex = requestedName.lastIndexOf('.');
        String baseName = dotIndex <= 0 ? requestedName : requestedName.substring(0, dotIndex);
        String extension = dotIndex <= 0 ? "" : requestedName.substring(dotIndex);
        int index = 1;
        while (nameExists(task, parentId, name)) {
            if (index > MAX_NAME_COLLISION_ITERATIONS) {
                name = baseName + " (" + UUID.randomUUID().toString().substring(0, 8) + ")" + extension;
                break;
            }
            name = baseName + " (" + index + ")" + extension;
            index++;
        }
        return name;
    }

    private boolean nameExists(StorageImportTask task, UUID parentId, String name) {
        if (resolveSpaceType(task) == SpaceType.SHARED) {
            return fileNodeRepository.existsBySpaceTypeAndParentIdAndNameAndDeletedFalse(
                    SpaceType.SHARED,
                    parentId,
                    name
            );
        }
        if (parentId == null) {
            return fileNodeRepository.existsByOwnerUserIdAndParentIdIsNullAndNameAndDeletedFalse(
                    task.getOwnerUserId(),
                    name
            );
        }
        return fileNodeRepository.existsByOwnerUserIdAndParentIdAndNameAndDeletedFalse(
                task.getOwnerUserId(),
                parentId,
                name
        );
    }

    private SpaceType resolveSpaceType(StorageImportTask task) {
        try {
            return SpaceType.fromValue(task.getSpaceType());
        } catch (IllegalArgumentException exception) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "导入目标空间不合法");
        }
    }

    private String resolveChildPath(FileNode parent, String childName) {
        if (parent == null) {
            return "/" + childName;
        }
        return parent.getNormalizedPath() + "/" + childName;
    }

    private String detectMimeType(Path file) {
        try {
            String mimeType = Files.probeContentType(file);
            if (mimeType != null && !mimeType.isBlank()) {
                return mimeType;
            }
        } catch (IOException e) {
            // 降级到扩展名推断
        }
        return FileUploadSessionService.guessMimeTypeByFileName(
                file.getFileName().toString());
    }

    private long fileSize(Path file) {
        try {
            return Files.size(file);
        } catch (IOException e) {
            throw new IllegalStateException("读取文件大小失败", e);
        }
    }

    private void cleanupTempDir(Path tempDir) {
        try {
            fileTreeScanner.deleteTree(tempDir);
        } catch (IOException ignored) {
            // 清理失败不影响主流程
        }
    }

    private String summarize(Exception exception) {
        String message = exception.getMessage();
        if (message == null || message.isBlank()) {
            return exception.getClass().getSimpleName();
        }
        return message.length() > 500 ? message.substring(0, 500) : message;
    }

    private void sleep(int seconds) {
        try {
            Thread.sleep(Duration.ofSeconds(seconds).toMillis());
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("导入轮询被中断", e);
        }
    }
}
