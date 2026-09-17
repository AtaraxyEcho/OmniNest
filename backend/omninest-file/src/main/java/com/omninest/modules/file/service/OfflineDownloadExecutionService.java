package com.omninest.modules.file.service;

import com.omninest.common.download.OfflineDownloadGateway;
import com.omninest.common.download.OfflineDownloadGateway.DownloadedFile;
import com.omninest.common.download.OfflineDownloadGateway.TaskSnapshot;
import com.omninest.common.download.OfflineDownloadSourceResolver;
import com.omninest.common.download.OfflineDownloadSourceResolver.ResolvedSource;
import com.omninest.common.download.OfflineDownloadSourceResolver.SourceKind;
import com.omninest.common.enums.ErrorCode;
import com.omninest.modules.file.domain.NodeType;
import com.omninest.modules.file.domain.SourceType;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.task.domain.TaskStatus;
import com.omninest.common.error.BusinessException;
import com.omninest.common.security.SafeUrlValidator;
import com.omninest.common.messaging.DomainEventPublisher;
import com.omninest.common.messaging.QueueNames;
import com.omninest.common.storage.ObjectStorageBuckets;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.common.storage.ObjectStorageKey;
import com.omninest.modules.file.domain.DownloadOfflineTask;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.FileObject;
import com.omninest.modules.file.event.FileUploadedEvent;
import com.omninest.modules.file.event.OfflineDownloadRequestedEvent;
import com.omninest.modules.file.service.FileIngressSafetyService.InspectionResult;
import com.omninest.modules.file.service.FileIngressLifecycleService.IngressCommand;
import com.omninest.modules.file.repository.DownloadOfflineTaskRepository;
import com.omninest.modules.file.repository.FileNodeRepository;
import com.omninest.modules.file.repository.FileObjectRepository;
import com.omninest.modules.notification.port.NotificationPublisher;
import com.omninest.modules.quota.service.StorageQuotaService;
import com.omninest.modules.task.service.TaskRecordService;
import com.omninest.common.util.ThrowableDescriber;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.Path;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.EnumSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

/**
 * 离线下载执行服务，负责调用 aria2、同步任务状态并将完成文件导入文件空间。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class OfflineDownloadExecutionService {
    private static final int MAX_TORRENT_BYTES = 32 * 1024 * 1024;
    private static final int MAX_HTTP_REDIRECTS = 5;

    private final DownloadOfflineTaskRepository offlineTaskRepository;
    private final FileNodeRepository fileNodeRepository;
    private final FileObjectRepository fileObjectRepository;
    private final StorageQuotaService storageQuotaService;
    private final ObjectStorageClient objectStorageClient;
    private final DomainEventPublisher domainEventPublisher;
    private final FilePostProcessingTaskService postProcessingTaskService;
    private final OfflineDownloadSourceResolver sourceResolver;
    private final OfflineDownloadGateway offlineDownloadGateway;
    private final ObjectStorageBuckets objectStorageBuckets;
    private final TransactionTemplate transactionTemplate;
    private final NotificationPublisher notificationService;
    private final TaskRecordService taskRecordService;
    private final SafeUrlValidator safeUrlValidator;
    private final BoundedFileTreeScanner fileTreeScanner;
    private final FileIngressSafetyService ingressSafetyService;
    private final FileIngressLifecycleService ingressLifecycleService;

    private final HttpClient httpClient = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(15))
            .followRedirects(HttpClient.Redirect.NEVER)
            .build();

    /**
     * 执行离线下载任务。
     *
     * @param event 离线下载请求事件
     */
    public void execute(OfflineDownloadRequestedEvent event) {
        Optional<DownloadOfflineTask> taskOpt = markRunning(event.taskId());
        if (taskOpt.isEmpty()) {
            log.warn("离线下载任务未能进入执行态: taskId={}", event.taskId());
            return;
        }
        DownloadOfflineTask task = taskOpt.get();
        Path taskDirectory = offlineDownloadGateway.downloadRoot()
                .resolve(task.getId().toString())
                .toAbsolutePath()
                .normalize();
        boolean downloadCompleted = false;
        try {
            createTaskDirectory(taskDirectory);
            ResolvedSource source = sourceResolver.resolve(task.getSourceUri());
            String gid = submitToAria2(source, taskDirectory);
            updateAria2Gid(task.getId(), gid);
            TaskSnapshot status = waitForCompletion(task.getId(), gid);
            if (status == null) {
                return;
            }
            downloadCompleted = true;
            List<Path> completedFiles = resolveCompletedFiles(taskDirectory, status);
            if (completedFiles.isEmpty()) {
                markFailed(task.getId(), "aria2 未生成可导入文件");
                return;
            }
            importCompletedFiles(task.getId(), taskDirectory, status, completedFiles);
        } catch (Exception exception) {
            log.warn("离线下载任务执行失败: taskId={}", task.getId(), exception);
            markFailed(task.getId(), summarize(exception), ThrowableDescriber.describe(exception));
        } finally {
            if (downloadCompleted) {
                cleanupCompletedDownload(taskDirectory);
            }
        }
    }

    private Optional<DownloadOfflineTask> markRunning(UUID taskId) {
        return transactionTemplate.execute(transactionStatus ->
                offlineTaskRepository.findById(taskId)
                        .filter(t -> TaskStatus.QUEUED.getValue().equals(t.getStatus()))
                        .map(t -> {
                            if (!taskRecordService.claimForExecution(systemTaskId(t), "DOWNLOADING")) {
                                return null;
                            }
                            t.setStatus(TaskStatus.RUNNING.getValue());
                            t.setErrorSummary(null);
                            return offlineTaskRepository.save(t);
                        })
        );
    }

    private void createTaskDirectory(Path taskDirectory) throws IOException {
        Files.createDirectories(taskDirectory);
        try {
            // Aria2 容器常以非 root 用户写入同一挂载；目录需对其可写。
            java.util.Set<java.nio.file.attribute.PosixFilePermission> perms = EnumSet.of(
                    java.nio.file.attribute.PosixFilePermission.OWNER_READ,
                    java.nio.file.attribute.PosixFilePermission.OWNER_WRITE,
                    java.nio.file.attribute.PosixFilePermission.OWNER_EXECUTE,
                    java.nio.file.attribute.PosixFilePermission.GROUP_READ,
                    java.nio.file.attribute.PosixFilePermission.GROUP_WRITE,
                    java.nio.file.attribute.PosixFilePermission.GROUP_EXECUTE,
                    java.nio.file.attribute.PosixFilePermission.OTHERS_READ,
                    java.nio.file.attribute.PosixFilePermission.OTHERS_WRITE,
                    java.nio.file.attribute.PosixFilePermission.OTHERS_EXECUTE
            );
            Files.setPosixFilePermissions(taskDirectory, perms);
        } catch (UnsupportedOperationException ignored) {
            // 非 POSIX 文件系统忽略
        }
    }

    private String submitToAria2(ResolvedSource source, Path taskDirectory) {
        Map<String, Object> options = new LinkedHashMap<>();
        options.put("dir", taskDirectory.toString());
        options.put("allow-overwrite", "false");
        options.put("auto-file-renaming", "true");
        options.put("bt-save-metadata", "true");
        options.put("bt-metadata-only", "false");
        options.put("seed-time", "0");
        options.put("follow-torrent", "true");
        if (source.kind() == SourceKind.TORRENT_FILE) {
            byte[] torrent = downloadTorrent(source.uri());
            return offlineDownloadGateway.submitTorrent(torrent, options);
        }
        return offlineDownloadGateway.submitUri(source.uri().toString(), options);
    }

    private byte[] downloadTorrent(URI uri) {
        URI current = uri;
        for (int redirect = 0; redirect <= MAX_HTTP_REDIRECTS; redirect++) {
            safeUrlValidator.requireSafeHost(current);
            sourceResolver.resolve(current.toString());
            HttpRequest request = HttpRequest.newBuilder(current)
                    .timeout(Duration.ofSeconds(30))
                    .GET()
                    .build();
            try {
                HttpResponse<InputStream> response = httpClient.send(
                        request,
                        HttpResponse.BodyHandlers.ofInputStream()
                );
                int statusCode = response.statusCode();
                if (statusCode >= 300 && statusCode < 400) {
                    String location = response.headers().firstValue("location")
                            .orElseThrow(() -> new BusinessException(ErrorCode.BAD_REQUEST, "BT 种子重定向缺少地址"));
                    current = current.resolve(location);
                    continue;
                }
                if (statusCode >= 400) {
                    throw new BusinessException(ErrorCode.BAD_REQUEST, "BT 种子下载失败，状态码=" + statusCode);
                }
                return readLimited(response.body());
            } catch (InterruptedException exception) {
                Thread.currentThread().interrupt();
                throw new IllegalStateException("BT 种子下载被中断", exception);
            } catch (IOException exception) {
                throw new IllegalStateException("BT 种子下载失败", exception);
            }
        }
        throw new BusinessException(ErrorCode.BAD_REQUEST, "BT 种子重定向次数过多");
    }

    private byte[] readLimited(InputStream inputStream) throws IOException {
        try (InputStream stream = inputStream; ByteArrayOutputStream outputStream = new ByteArrayOutputStream()) {
            byte[] buffer = new byte[8192];
            int total = 0;
            int read;
            while ((read = stream.read(buffer)) >= 0) {
                total += read;
                if (total > MAX_TORRENT_BYTES) {
                    throw new BusinessException(ErrorCode.FILE_SIZE_EXCEEDED, "BT 种子文件过大");
                }
                outputStream.write(buffer, 0, read);
            }
            return outputStream.toByteArray();
        }
    }

    private void updateAria2Gid(UUID taskId, String gid) {
        transactionTemplate.executeWithoutResult(status -> {
            DownloadOfflineTask task = requireTask(taskId);
            task.setAria2Gid(gid);
            offlineTaskRepository.save(task);
        });
    }

    private static final int MAX_RPC_RETRIES = 3;

    private TaskSnapshot waitForCompletion(UUID taskId, String gid) {
        int pollSeconds = Math.max(1, offlineDownloadGateway.pollIntervalSeconds());
        int consecutiveFailures = 0;
        Instant lastProgressAt = Instant.now();
        // 消费线程轮询硬上限，避免下载挂起时永久占用 worker。
        Instant deadline = Instant.now().plusSeconds(Math.max(pollSeconds, 30) * 240L);
        while (true) {
            if (Instant.now().isAfter(deadline)) {
                markFailed(taskId, "离线下载等待超时");
                return null;
            }
            if (isCancelled(taskId)) {
                offlineDownloadGateway.remove(gid);
                markCancelled(taskId);
                return null;
            }
            TaskSnapshot status;
            try {
                status = offlineDownloadGateway.queryStatus(gid);
                consecutiveFailures = 0;
            } catch (IllegalStateException exception) {
                consecutiveFailures++;
                log.warn("aria2 状态查询失败 ({}): taskId={}, gid={}, message={}",
                        consecutiveFailures, taskId, gid, exception.getMessage());
                if (consecutiveFailures >= MAX_RPC_RETRIES) {
                    markFailed(taskId, "aria2 连接失败，已重试 " + MAX_RPC_RETRIES + " 次");
                    return null;
                }
                sleep(pollSeconds);
                continue;
            }
            // 无进度变化超过总超时阈值时判定失败退出，避免消费线程永久占用。
            if (hasProgressAdvanced(status)) {
                lastProgressAt = Instant.now();
            } else if (Duration.between(lastProgressAt, Instant.now())
                    .compareTo(offlineDownloadGateway.idleTimeout()) > 0) {
                markFailed(taskId, "下载长时间无进度，已超时中止");
                return null;
            }
            updateProgress(taskId, status);
            if ("complete".equals(status.state())) {
                return status;
            }
            if ("error".equals(status.state()) || "removed".equals(status.state())) {
                markFailed(taskId, status.errorMessage() == null ? "aria2 下载失败" : status.errorMessage());
                return null;
            }
            sleep(pollSeconds);
        }
    }

    private boolean hasProgressAdvanced(TaskSnapshot status) {
        return status.completedBytes() > 0 || status.speedBytes() > 0
                || "active".equals(status.state()) == false;
    }

    private boolean isCancelled(UUID taskId) {
        return Boolean.TRUE.equals(transactionTemplate.execute(status -> offlineTaskRepository.findById(taskId)
                .map(task -> TaskStatus.CANCELLED.getValue().equals(task.getStatus()))
                .orElse(true)));
    }

    private void updateProgress(UUID taskId, TaskSnapshot status) {
        transactionTemplate.executeWithoutResult(transactionStatus -> {
            DownloadOfflineTask task = requireTask(taskId);
            if (TaskStatus.CANCELLED.getValue().equals(task.getStatus())) {
                return;
            }
            task.setStatus(TaskStatus.RUNNING.getValue());
            task.setTotalBytes(status.totalBytes());
            task.setCompletedBytes(status.completedBytes());
            task.setDownloadSpeedBytes(status.speedBytes());
            task.setFileName(resolveDisplayName(status).orElse(task.getFileName()));
            offlineTaskRepository.save(task);
            taskRecordService.updateProgress(systemTaskId(task), progressFromStatus(status));
        });
    }

    private void importCompletedFiles(
            UUID taskId,
            Path taskDirectory,
            TaskSnapshot status,
            List<Path> completedFiles
    ) {
        transactionTemplate.executeWithoutResult(transactionStatus -> {
            DownloadOfflineTask task = requireTask(taskId);
            if (TaskStatus.CANCELLED.getValue().equals(task.getStatus())) {
                return;
            }
            long totalSize = totalSize(completedFiles);
            storageQuotaService.reserve(
                    task.getOwnerUserId(),
                    "OFFLINE_DOWNLOAD",
                    task.getId(),
                    totalSize,
                    Instant.now().plus(Duration.ofHours(24))
            );
            FileNode targetParent = resolveParent(task.getOwnerUserId(), task.getTargetParentId());
            FileNode importRoot = createImportRootIfNeeded(task, targetParent, status, completedFiles);
            FileNode completedNode = importFiles(task, taskDirectory, targetParent, importRoot, completedFiles);
            storageQuotaService.settleReservation("OFFLINE_DOWNLOAD", task.getId(), totalSize);
            task.setStatus(TaskStatus.COMPLETED.getValue());
            task.setTotalBytes(totalSize);
            task.setCompletedBytes(totalSize);
            task.setDownloadSpeedBytes(0L);
            task.setCompletedFileId(completedNode.getId());
            task.setCompletedAt(Instant.now());
            task.setFileName(completedNode.getName());
            task.setErrorSummary(null);
            offlineTaskRepository.save(task);
        });
        // 发送完成通知
        DownloadOfflineTask completedTask = offlineTaskRepository.findById(taskId).orElse(null);
        if (completedTask != null) {
            taskRecordService.markCompleted(systemTaskId(completedTask), Map.of(
                    "completedFileId", completedTask.getCompletedFileId().toString(),
                    "fileName", completedTask.getFileName(),
                    "totalBytes", completedTask.getTotalBytes()));
            notificationService.notifyOrLog(completedTask.getOwnerUserId(), "TASK_COMPLETED",
                    "离线下载完成", "文件 " + completedTask.getFileName() + " 已下载完成",
                    Map.of("taskId", taskId.toString()));
        }
    }

    private FileNode createImportRootIfNeeded(
            DownloadOfflineTask task,
            FileNode targetParent,
            TaskSnapshot status,
            List<Path> completedFiles
    ) {
        if (completedFiles.size() == 1) {
            return null;
        }
        String rootName = normalizeFileName(resolveDisplayName(status)
                .orElse("offline-" + task.getId().toString().substring(0, 8)));
        String availableName = resolveAvailableName(
                task.getOwnerUserId(),
                targetParent == null ? null : targetParent.getId(),
                rootName
        );
        FileNode folder = new FileNode();
        folder.setOwnerUserId(task.getOwnerUserId());
        folder.setParentId(targetParent == null ? null : targetParent.getId());
        folder.setNodeType(NodeType.FOLDER.getValue());
        folder.setName(availableName);
        folder.setNormalizedPath(resolveChildPath(targetParent, availableName));
        folder.setSizeBytes(0L);
        folder.setSourceType(SourceType.LOCAL.getValue());
        folder.setSpaceType(resolveSpaceType(task));
        return fileNodeRepository.save(folder);
    }

    private FileNode importFiles(
            DownloadOfflineTask task,
            Path taskDirectory,
            FileNode targetParent,
            FileNode importRoot,
            List<Path> completedFiles
    ) {
        FileNode lastImported = importRoot;
        Map<Path, FileNode> folderCache = new LinkedHashMap<>();
        for (Path file : completedFiles) {
            Path relative = taskDirectory.relativize(file).normalize();
            FileNode parent = importRoot == null
                    ? targetParent
                    : resolveNestedParent(task.getOwnerUserId(), importRoot, relative.getParent(), folderCache, resolveSpaceType(task));
            lastImported = importSingleFile(task, parent, file, relative.getFileName().toString());
        }
        if (lastImported == null) {
            throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "离线下载导入失败");
        }
        return importRoot == null ? lastImported : importRoot;
    }

    private FileNode resolveNestedParent(
            UUID ownerUserId,
            FileNode importRoot,
            Path relativeParent,
            Map<Path, FileNode> folderCache,
            SpaceType spaceType
    ) {
        if (relativeParent == null) {
            return importRoot;
        }
        FileNode current = importRoot;
        Path currentPath = Path.of("");
        for (Path segment : relativeParent) {
            String folderName = normalizeFileName(segment.toString());
            currentPath = currentPath.resolve(folderName);
            FileNode cached = folderCache.get(currentPath);
            if (cached != null) {
                current = cached;
                continue;
            }
            String availableName = resolveAvailableName(ownerUserId, current.getId(), folderName);
            FileNode folder = new FileNode();
            folder.setOwnerUserId(ownerUserId);
            folder.setParentId(current.getId());
            folder.setNodeType(NodeType.FOLDER.getValue());
            folder.setName(availableName);
            folder.setNormalizedPath(resolveChildPath(current, availableName));
            folder.setSizeBytes(0L);
            folder.setSourceType(SourceType.LOCAL.getValue());
            folder.setSpaceType(spaceType);
            current = fileNodeRepository.save(folder);
            folderCache.put(currentPath, current);
        }
        return current;
    }

    private SpaceType resolveSpaceType(DownloadOfflineTask task) {
        if (task.getSpaceType() == null || task.getSpaceType().isBlank()) {
            return SpaceType.PERSONAL;
        }
        try {
            return SpaceType.fromValue(task.getSpaceType());
        } catch (IllegalArgumentException exception) {
            return SpaceType.PERSONAL;
        }
    }

    private FileNode importSingleFile(DownloadOfflineTask task, FileNode parent, Path source, String rawFileName) {
        String fileName = normalizeFileName(rawFileName);
        String availableName = resolveAvailableName(
                task.getOwnerUserId(),
                parent == null ? null : parent.getId(),
                fileName
        );
        String quarantineObjectKey = "offline-downloads/" + task.getOwnerUserId()
                + "/" + task.getId()
                + "/" + UUID.randomUUID()
                + "/" + availableName;
        String targetObjectKey = "users/" + task.getOwnerUserId()
                + "/offline-downloads/" + task.getId()
                + "/" + UUID.randomUUID()
                + "/" + availableName;
        String mimeType = detectMimeType(source);
        long sizeBytes = size(source);
        ObjectStorageKey quarantineKey = new ObjectStorageKey(
                objectStorageBuckets.quarantine(),
                quarantineObjectKey
        );
        ObjectStorageKey targetKey = new ObjectStorageKey(
                objectStorageBuckets.userFiles(),
                targetObjectKey
        );
        objectStorageClient.putObject(quarantineKey, source, mimeType);
        UUID ingressId = ingressLifecycleService.open(new IngressCommand(
                task.getOwnerUserId(),
                "OFFLINE",
                task.getId(),
                null,
                quarantineKey.bucket(),
                quarantineKey.objectKey(),
                targetKey.bucket(),
                targetKey.objectKey(),
                parent == null ? null : parent.getId(),
                availableName,
                sizeBytes,
                mimeType
        ));
        ingressLifecycleService.markScanning(ingressId);
        InspectionResult inspection;
        try {
            inspection = ingressSafetyService.inspect(
                    quarantineKey,
                    sizeBytes,
                    "OFFLINE",
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

        FileObject object = new FileObject();
        object.setBucketName(targetKey.bucket());
        object.setObjectKey(targetKey.objectKey());
        object.setSha256(inspection.sha256());
        object.setSizeBytes(sizeBytes);
        object.setMimeType(mimeType);
        FileObject savedObject = fileObjectRepository.save(object);

        FileNode fileNode = new FileNode();
        fileNode.setOwnerUserId(task.getOwnerUserId());
        fileNode.setParentId(parent == null ? null : parent.getId());
        fileNode.setNodeType(NodeType.FILE.getValue());
        fileNode.setName(availableName);
        fileNode.setNormalizedPath(resolveChildPath(parent, availableName));
        fileNode.setMimeType(mimeType);
        fileNode.setSizeBytes(savedObject.getSizeBytes());
        fileNode.setCurrentObjectId(savedObject.getId());
        fileNode.setSourceType(SourceType.LOCAL.getValue());
        fileNode.setSpaceType(resolveSpaceType(task));
        FileNode savedFile = fileNodeRepository.save(fileNode);
        registerObjectFinalization(quarantineKey, targetKey, ingressId, savedFile.getId());
        publishFileUploaded(savedFile, savedObject);
        return savedFile;
    }

    private void registerObjectFinalization(
            ObjectStorageKey quarantineKey,
            ObjectStorageKey targetKey,
            UUID ingressId,
            UUID fileNodeId
    ) {
        if (!TransactionSynchronizationManager.isSynchronizationActive()) {
            markIngressAvailableQuietly(ingressId, fileNodeId);
            removeObjectQuietly(quarantineKey);
            return;
        }
        TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
            @Override
            public void afterCompletion(int status) {
                if (status == TransactionSynchronization.STATUS_COMMITTED) {
                    markIngressAvailableQuietly(ingressId, fileNodeId);
                    removeObjectQuietly(quarantineKey);
                    return;
                }
                ingressLifecycleService.markFailed(
                        ingressId,
                        false,
                        ErrorCode.FILE_UPLOAD_FAILED.name(),
                        "离线下载业务元数据提交失败"
                );
                removeObjectQuietly(targetKey);
            }
        });
    }

    private void markIngressAvailableQuietly(UUID ingressId, UUID fileNodeId) {
        try {
            ingressLifecycleService.markAvailable(ingressId, fileNodeId);
        } catch (RuntimeException exception) {
            log.warn("更新离线下载入库可用状态失败: ingressId={}, errorType={}",
                    ingressId, exception.getClass().getSimpleName());
        }
    }

    private void removeObjectQuietly(ObjectStorageKey key) {
        try {
            objectStorageClient.removeObject(key);
        } catch (RuntimeException exception) {
            log.warn("清理离线下载入库临时对象失败: bucket={}, errorType={}",
                    key.bucket(), exception.getClass().getSimpleName());
        }
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

    private List<Path> resolveCompletedFiles(Path taskDirectory, TaskSnapshot status) {
        List<Path> files = new ArrayList<>();
        for (DownloadedFile item : status.files()) {
            if (!item.selected()) {
                continue;
            }
            String rawPath = item.path();
            if (rawPath == null || rawPath.isBlank()) {
                continue;
            }
            Path path = Path.of(rawPath).toAbsolutePath().normalize();
            if (path.startsWith(taskDirectory)
                    && Files.isRegularFile(path, LinkOption.NOFOLLOW_LINKS)) {
                files.add(path);
            }
        }
        if (!files.isEmpty()) {
            return files.stream().distinct().sorted().toList();
        }
        try {
            return fileTreeScanner.listRegularFiles(taskDirectory);
        } catch (IOException exception) {
            throw new IllegalStateException("读取离线下载结果失败", exception);
        }
    }

    private Optional<String> resolveDisplayName(TaskSnapshot status) {
        return Optional.ofNullable(status.displayName()).filter(name -> !name.isBlank());
    }

    private FileNode resolveParent(UUID ownerUserId, UUID parentId) {
        if (parentId == null) {
            return null;
        }
        FileNode parent = fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(parentId, ownerUserId)
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "父级文件夹不存在"));
        if (!NodeType.FOLDER.getValue().equals(parent.getNodeType())) {
            throw new BusinessException(ErrorCode.FILE_PATH_INVALID, "父级节点不是文件夹");
        }
        return parent;
    }

    private static final int MAX_NAME_COLLISION_ITERATIONS = 1000;

    private String resolveAvailableName(UUID ownerUserId, UUID parentId, String requestedName) {
        String name = requestedName;
        int dotIndex = requestedName.lastIndexOf('.');
        String baseName = dotIndex <= 0 ? requestedName : requestedName.substring(0, dotIndex);
        String extension = dotIndex <= 0 ? "" : requestedName.substring(dotIndex);
        int index = 1;
        while (sameNameExists(ownerUserId, parentId, name)) {
            if (index > MAX_NAME_COLLISION_ITERATIONS) {
                name = baseName + " (" + UUID.randomUUID().toString().substring(0, 8) + ")" + extension;
                break;
            }
            name = baseName + " (" + index + ")" + extension;
            index++;
        }
        return name;
    }

    private boolean sameNameExists(UUID ownerUserId, UUID parentId, String name) {
        if (parentId == null) {
            return fileNodeRepository.existsByOwnerUserIdAndParentIdIsNullAndNameAndDeletedFalse(ownerUserId, name);
        }
        return fileNodeRepository.existsByOwnerUserIdAndParentIdAndNameAndDeletedFalse(ownerUserId, parentId, name);
    }

    private String normalizeFileName(String rawName) {
        String name = rawName == null ? "" : rawName.trim();
        if (name.isEmpty()
                || ".".equals(name)
                || "..".equals(name)
                || name.contains("/")
                || name.contains("\\")
                || name.contains("\u0000")) {
            return "download-" + UUID.randomUUID();
        }
        return name;
    }

    private String resolveChildPath(FileNode parent, String childName) {
        if (parent == null) {
            return "/" + childName;
        }
        return parent.getNormalizedPath() + "/" + childName;
    }

    private String detectMimeType(Path source) {
        try {
            String mimeType = Files.probeContentType(source);
            if (mimeType != null && !mimeType.isBlank()) {
                return mimeType;
            }
        } catch (IOException exception) {
            // 降级到扩展名推断
        }
        return FileUploadSessionService.guessMimeTypeByFileName(
                source.getFileName().toString());
    }

    private long totalSize(List<Path> files) {
        return files.stream().mapToLong(this::size).sum();
    }

    private long size(Path file) {
        try {
            return Files.size(file);
        } catch (IOException exception) {
            throw new IllegalStateException("读取文件大小失败", exception);
        }
    }

    private void cleanupCompletedDownload(Path taskDirectory) {
        Path downloadRoot = offlineDownloadGateway.downloadRoot().toAbsolutePath().normalize();
        if (taskDirectory.equals(downloadRoot) || !taskDirectory.startsWith(downloadRoot)) {
            log.warn("拒绝清理下载根目录之外的任务目录: taskDirectory={}", taskDirectory);
            return;
        }
        if (!Files.exists(taskDirectory)) {
            return;
        }
        try {
            fileTreeScanner.deleteTree(taskDirectory);
        } catch (IOException exception) {
            log.warn("清理离线下载暂存目录失败: taskDirectory={}, errorType={}",
                    taskDirectory, exception.getClass().getSimpleName());
        }
    }

    private void markCancelled(UUID taskId) {
        transactionTemplate.executeWithoutResult(status -> {
            DownloadOfflineTask task = requireTask(taskId);
            storageQuotaService.releaseReservation("OFFLINE_DOWNLOAD", task.getId());
            task.setStatus(TaskStatus.CANCELLED.getValue());
            task.setDownloadSpeedBytes(0L);
            offlineTaskRepository.save(task);
            taskRecordService.markCancelled(systemTaskId(task));
        });
    }

    private void markFailed(UUID taskId, String errorSummary) {
        markFailed(taskId, errorSummary, null);
    }

    private void markFailed(UUID taskId, String errorSummary, String stackSummary) {
        transactionTemplate.executeWithoutResult(status -> {
            DownloadOfflineTask task = requireTask(taskId);
            if (TaskStatus.CANCELLED.getValue().equals(task.getStatus())) {
                return;
            }
            storageQuotaService.releaseReservation("OFFLINE_DOWNLOAD", task.getId());
            task.setStatus(TaskStatus.FAILED.getValue());
            task.setDownloadSpeedBytes(0L);
            task.setErrorSummary(errorSummary);
            offlineTaskRepository.save(task);
        });
        // 发送失败通知
        DownloadOfflineTask failedTask = offlineTaskRepository.findById(taskId).orElse(null);
        if (failedTask != null) {
            taskRecordService.markFailed(systemTaskId(failedTask), errorSummary, stackSummary);
            notificationService.notifyOrLog(failedTask.getOwnerUserId(), "TASK_FAILED",
                    "离线下载失败", "下载失败: " + errorSummary,
                    Map.of("taskId", taskId.toString()));
        }
    }

    private UUID systemTaskId(DownloadOfflineTask task) {
        return task.getTaskId() == null ? task.getId() : task.getTaskId();
    }

    private int progressFromStatus(TaskSnapshot status) {
        if (status.totalBytes() <= 0L) {
            return 10;
        }
        long percent = Math.round(status.completedBytes() * 100.0d / status.totalBytes());
        return (int) Math.max(10L, Math.min(99L, percent));
    }

    private DownloadOfflineTask requireTask(UUID taskId) {
        return offlineTaskRepository.findById(taskId)
                .orElseThrow(() -> new BusinessException(ErrorCode.TASK_NOT_FOUND, "离线下载任务不存在"));
    }

    private String summarize(Exception exception) {
        String message = exception.getMessage();
        if (message == null || message.isBlank()) {
            return exception.getClass().getSimpleName();
        }
        return message.length() > 500 ? message.substring(0, 500) : message;
    }

    private void sleep(int pollSeconds) {
        try {
            Thread.sleep(Duration.ofSeconds(pollSeconds).toMillis());
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("离线下载轮询被中断", exception);
        }
    }
}
