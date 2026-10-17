package com.omninest.modules.file.service;

import com.omninest.common.download.OfflineDownloadGateway;
import com.omninest.common.download.OfflineDownloadGateway.DownloadedFile;
import com.omninest.common.download.OfflineDownloadGateway.TaskSnapshot;
import com.omninest.common.download.OfflineDownloadSourceResolver;
import com.omninest.common.download.OfflineDownloadSourceResolver.ResolvedSource;
import com.omninest.common.download.OfflineDownloadSourceResolver.SourceKind;
import com.omninest.common.download.TorrentAddressValidator;
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
import java.nio.file.attribute.PosixFilePermission;
import java.util.EnumSet;
import java.util.Set;
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
    private final SharedSpaceQuotaService sharedSpaceQuotaService;
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
    private final TorrentAddressValidator torrentAddressValidator;
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
            Set<PosixFilePermission> perms = EnumSet.of(
                    PosixFilePermission.OWNER_READ,
                    PosixFilePermission.OWNER_WRITE,
                    PosixFilePermission.OWNER_EXECUTE
            );
            Files.setPosixFilePermissions(taskDirectory, perms);
        } catch (UnsupportedOperationException exception) {
            log.debug("skip posix permission tighten on non-posix fs: {}", taskDirectory);
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
        // mem 与 true 同样跟随种子内容，但种子本体不落下载目录：否则 resolveCompletedFiles
        // 会把 .torrent 当成一个已完成文件导入用户空间。
        options.put("follow-torrent", "mem");
        if (source.kind() == SourceKind.TORRENT_FILE) {
            byte[] torrent = downloadTorrent(source.uri());
            return offlineDownloadGateway.submitTorrent(torrent, options);
        }
        if (source.kind() == SourceKind.HTTP) {
            // 应用侧逐跳校验重定向后再投递最终地址，并禁止 Aria2 继续跟随跳转。
            URI finalUri = resolveFinalSafeHttpUri(source.uri());
            options.put("max-redirect", "0");
            return offlineDownloadGateway.submitUri(finalUri.toString(), options);
        }
        return offlineDownloadGateway.submitUri(source.uri().toString(), options);
    }

    /**
     * 逐跳校验并解析 HTTP(S) 重定向，返回最终安全地址。
     */
    private URI resolveFinalSafeHttpUri(URI uri) {
        URI current = uri;
        for (int redirect = 0; redirect <= MAX_HTTP_REDIRECTS; redirect++) {
            safeUrlValidator.requireSafeHost(current);
            sourceResolver.resolve(current.toString());
            HttpRequest request = HttpRequest.newBuilder(current)
                    .timeout(Duration.ofSeconds(30))
                    .method("HEAD", HttpRequest.BodyPublishers.noBody())
                    .build();
            try {
                HttpResponse<Void> response = httpClient.send(
                        request,
                        HttpResponse.BodyHandlers.discarding()
                );
                int statusCode = response.statusCode();
                if (statusCode >= 300 && statusCode < 400) {
                    String location = response.headers().firstValue("location")
                            .orElseThrow(() -> new BusinessException(ErrorCode.BAD_REQUEST, "下载源重定向缺少地址"));
                    current = current.resolve(location);
                    continue;
                }
                return current;
            } catch (InterruptedException exception) {
                Thread.currentThread().interrupt();
                throw new IllegalStateException("下载源重定向解析被中断", exception);
            } catch (IOException exception) {
                throw new IllegalStateException("下载源重定向解析失败", exception);
            }
        }
        throw new BusinessException(ErrorCode.BAD_REQUEST, "下载源重定向次数过多");
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
                byte[] torrent = readLimited(response.body());
                // 种子内部的 announce 与 url-list 由下载器自行发起请求，提交前必须过一次闸门。
                torrentAddressValidator.validate(torrent);
                return torrent;
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
        DownloadOfflineTask snapshot = requireTask(taskId);
        if (TaskStatus.CANCELLED.getValue().equals(snapshot.getStatus())) {
            return;
        }
        long totalSize = totalSize(completedFiles);
        boolean sharedTarget = resolveSpaceType(snapshot) == SpaceType.SHARED;
        reserveImportCapacity(snapshot, sharedTarget, totalSize);

        // 阶段 A：多 GB 上传、ClamAV 扫描与桶间复制全部在事务外完成。此前这些 I/O 处在一个
        // 覆盖整批的数据库事务内，最长可达数十分钟；worker 池只有 6 条连接，几路并发入库就会
        // 把连接占满，而入库链路上的 ingress 生命周期方法还是 REQUIRES_NEW，会在持有连接的
        // 同时再抢一条。失败时不做额外补偿：异常冒泡到 execute() 的 markFailed，由其释放预留。
        List<StagedOfflineFile> stagedFiles = stageOfflineFiles(snapshot, taskDirectory, completedFiles);

        // 阶段 B：短事务只写 file_objects、file_nodes、共享用量与任务终态。
        List<ImportedOfflineFile> imported = transactionTemplate.execute(transactionStatus ->
                persistImportedBatch(taskId, status, completedFiles.size(), stagedFiles, totalSize, sharedTarget));
        if (imported == null) {
            return;
        }
        // 阶段 C：元数据提交后再投递索引与媒体自动导入事件，消费者不会读到未提交节点。
        imported.forEach(item -> publishFileUploaded(item.node(), item.object()));
    }

    private List<ImportedOfflineFile> persistImportedBatch(
            UUID taskId,
            TaskSnapshot status,
            int completedFileCount,
            List<StagedOfflineFile> stagedFiles,
            long totalSize,
            boolean sharedTarget
    ) {
        DownloadOfflineTask task = requireTask(taskId);
        if (TaskStatus.CANCELLED.getValue().equals(task.getStatus())) {
            releaseImportCapacity(task, sharedTarget);
            discardStagedFiles(stagedFiles);
            return List.of();
        }
        FileNode targetParent = resolveParent(task.getOwnerUserId(), task.getTargetParentId(), resolveSpaceType(task));
        FileNode importRoot = createImportRootIfNeeded(task, targetParent, status, completedFileCount);
        List<ImportedOfflineFile> imported = persistStagedFiles(task, targetParent, importRoot, stagedFiles);
        settleImportCapacity(task, sharedTarget, totalSize, completedFileCount);
        task.setStatus(TaskStatus.COMPLETED.getValue());
        task.setTotalBytes(totalSize);
        task.setCompletedBytes(totalSize);
        task.setDownloadSpeedBytes(0L);
        task.setCompletedFileId(terminalNodeId(imported, importRoot));
        task.setCompletedAt(Instant.now());
        task.setFileName(imported.isEmpty() ? task.getFileName() : imported.getLast().node().getName());
        task.setErrorSummary(null);
        offlineTaskRepository.save(task);
        registerPostImportNotification(taskId);
        return imported;
    }

    /**
     * 事务提交后再通知与投递派生任务：元数据未落库时不得让索引与媒体导入看见文件。
     */
    private void registerPostImportNotification(UUID taskId) {
        if (!TransactionSynchronizationManager.isSynchronizationActive()) {
            publishImportNotifications(taskId);
            return;
        }
        TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
            @Override
            public void afterCommit() {
                publishImportNotifications(taskId);
            }
        });
    }

    private void publishImportNotifications(UUID taskId) {
        DownloadOfflineTask completedTask = offlineTaskRepository.findById(taskId).orElse(null);
        if (completedTask == null || completedTask.getCompletedFileId() == null) {
            return;
        }
        taskRecordService.markCompleted(systemTaskId(completedTask), Map.of(
                "completedFileId", completedTask.getCompletedFileId().toString(),
                "fileName", String.valueOf(completedTask.getFileName()),
                "totalBytes", completedTask.getTotalBytes()));
        notificationService.notifyOrLog(completedTask.getOwnerUserId(), "TASK_COMPLETED",
                "离线下载完成", "文件 " + completedTask.getFileName() + " 已下载完成",
                Map.of("taskId", taskId.toString()));
    }

    private void reserveImportCapacity(DownloadOfflineTask task, boolean sharedTarget, long totalSize) {
        if (sharedTarget) {
            // 共享空间无预留机制：入库前复核容量，完成时按实际计入共享用量
            sharedSpaceQuotaService.checkQuota(totalSize);
            return;
        }
        storageQuotaService.reserve(
                task.getOwnerUserId(),
                "OFFLINE_DOWNLOAD",
                task.getId(),
                totalSize,
                Instant.now().plus(Duration.ofHours(24))
        );
    }

    private void settleImportCapacity(
            DownloadOfflineTask task,
            boolean sharedTarget,
            long totalSize,
            int importedFileCount
    ) {
        if (sharedTarget) {
            sharedSpaceQuotaService.increaseUsage(totalSize, importedFileCount);
            return;
        }
        storageQuotaService.settleReservation("OFFLINE_DOWNLOAD", task.getId(), totalSize);
    }

    private void releaseImportCapacity(DownloadOfflineTask task, boolean sharedTarget) {
        if (sharedTarget) {
            return;
        }
        storageQuotaService.releaseReservation("OFFLINE_DOWNLOAD", task.getId());
    }

    private UUID terminalNodeId(List<ImportedOfflineFile> imported, FileNode importRoot) {
        if (importRoot != null) {
            return importRoot.getId();
        }
        if (imported.isEmpty()) {
            throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "离线下载导入失败");
        }
        return imported.getLast().node().getId();
    }

    private FileNode createImportRootIfNeeded(
            DownloadOfflineTask task,
            FileNode targetParent,
            TaskSnapshot status,
            int completedFileCount
    ) {
        if (completedFileCount == 1) {
            return null;
        }
        String rootName = normalizeFileName(resolveDisplayName(status)
                .orElse("offline-" + task.getId().toString().substring(0, 8)));
        String availableName = resolveAvailableName(
                task.getOwnerUserId(),
                resolveSpaceType(task),
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

    /**
     * 阶段 A 产物：内容已上传并通过扫描，尚未写入业务元数据。
     *
     * @param relativeParent 相对下载目录的父级路径，用于在事务内还原目录层级
     * @param fileName 未做重名去重的规范化文件名
     * @param quarantineKey 隔离桶对象
     * @param targetKey 正式桶对象
     * @param ingressId 入库记录标识
     * @param sha256 服务端摘要
     * @param sizeBytes 字节数
     * @param mimeType MIME 类型
     */
    private record StagedOfflineFile(
            Path relativeParent,
            String fileName,
            ObjectStorageKey quarantineKey,
            ObjectStorageKey targetKey,
            UUID ingressId,
            String sha256,
            long sizeBytes,
            String mimeType
    ) {
    }

    /**
     * 阶段 B 产物：已落库的节点与内容对象，供阶段 C 投递事件。
     *
     * @param node 文件节点
     * @param object 内容对象
     */
    private record ImportedOfflineFile(FileNode node, FileObject object) {
    }

    private List<StagedOfflineFile> stageOfflineFiles(
            DownloadOfflineTask task,
            Path taskDirectory,
            List<Path> completedFiles
    ) {
        List<StagedOfflineFile> staged = new ArrayList<>();
        try {
            for (Path file : completedFiles) {
                Path relative = taskDirectory.relativize(file).normalize();
                staged.add(stageOfflineFile(task, file, relative));
            }
            return staged;
        } catch (RuntimeException exception) {
            // 事务尚未开启，本批已暂存的对象无人回滚，必须就地清理，否则隔离与正式桶只等回收器兜底。
            discardStagedFiles(staged);
            throw exception;
        }
    }

    private StagedOfflineFile stageOfflineFile(DownloadOfflineTask task, Path source, Path relative) {
        String fileName = normalizeFileName(relative.getFileName().toString());
        String quarantineObjectKey = "offline-downloads/" + task.getOwnerUserId()
                + "/" + task.getId()
                + "/" + UUID.randomUUID()
                + "/" + fileName;
        String targetObjectKey = "users/" + task.getOwnerUserId()
                + "/offline-downloads/" + task.getId()
                + "/" + UUID.randomUUID()
                + "/" + fileName;
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
                task.getTargetParentId(),
                fileName,
                sizeBytes,
                mimeType
        ));
        ingressLifecycleService.markScanning(ingressId);
        InspectionResult inspection;
        try {
            inspection = ingressSafetyService.inspect(
                    quarantineKey,
                    sizeBytes,
                    null,
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
        return new StagedOfflineFile(
                relative.getParent(),
                fileName,
                quarantineKey,
                targetKey,
                ingressId,
                inspection.sha256(),
                sizeBytes,
                mimeType
        );
    }

    private void discardStagedFiles(List<StagedOfflineFile> stagedFiles) {
        for (StagedOfflineFile staged : stagedFiles) {
            try {
                ingressLifecycleService.markFailed(
                        staged.ingressId(),
                        false,
                        ErrorCode.FILE_UPLOAD_FAILED.name(),
                        "离线下载导入未完成"
                );
            } catch (RuntimeException exception) {
                log.warn("标记离线下载入库记录失败: ingressId={}, errorType={}",
                        staged.ingressId(), exception.getClass().getSimpleName());
            }
            // 隔离对象留给隔离回收器按保留期处理，正式桶副本无人引用，立即删除。
            removeObjectQuietly(staged.targetKey());
        }
    }

    private List<ImportedOfflineFile> persistStagedFiles(
            DownloadOfflineTask task,
            FileNode targetParent,
            FileNode importRoot,
            List<StagedOfflineFile> stagedFiles
    ) {
        SpaceType spaceType = resolveSpaceType(task);
        List<ImportedOfflineFile> imported = new ArrayList<>();
        Map<Path, FileNode> folderCache = new LinkedHashMap<>();
        for (StagedOfflineFile staged : stagedFiles) {
            FileNode parent = importRoot == null
                    ? targetParent
                    : resolveNestedParent(
                            task.getOwnerUserId(),
                            importRoot,
                            staged.relativeParent(),
                            folderCache,
                            spaceType);
            imported.add(persistStagedFile(task, parent, staged, spaceType));
        }
        return imported;
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
            String availableName = resolveAvailableName(ownerUserId, spaceType, current.getId(), folderName);
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

    private ImportedOfflineFile persistStagedFile(
            DownloadOfflineTask task,
            FileNode parent,
            StagedOfflineFile staged,
            SpaceType spaceType
    ) {
        String availableName = resolveAvailableName(
                task.getOwnerUserId(),
                spaceType,
                parent == null ? null : parent.getId(),
                staged.fileName()
        );
        FileObject object = new FileObject();
        object.setBucketName(staged.targetKey().bucket());
        object.setObjectKey(staged.targetKey().objectKey());
        object.setSha256(staged.sha256());
        object.setSizeBytes(staged.sizeBytes());
        object.setMimeType(staged.mimeType());
        FileObject savedObject = fileObjectRepository.save(object);

        FileNode fileNode = new FileNode();
        fileNode.setOwnerUserId(task.getOwnerUserId());
        fileNode.setParentId(parent == null ? null : parent.getId());
        fileNode.setNodeType(NodeType.FILE.getValue());
        fileNode.setName(availableName);
        fileNode.setNormalizedPath(resolveChildPath(parent, availableName));
        fileNode.setMimeType(staged.mimeType());
        fileNode.setSizeBytes(savedObject.getSizeBytes());
        fileNode.setCurrentObjectId(savedObject.getId());
        fileNode.setSourceType(SourceType.LOCAL.getValue());
        fileNode.setSpaceType(spaceType);
        FileNode savedFile = fileNodeRepository.save(fileNode);
        registerObjectFinalization(
                staged.quarantineKey(),
                staged.targetKey(),
                staged.ingressId(),
                savedFile.getId()
        );
        return new ImportedOfflineFile(savedFile, savedObject);
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

    private FileNode resolveParent(UUID ownerUserId, UUID parentId, SpaceType spaceType) {
        if (parentId == null) {
            return null;
        }
        FileNode parent = fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(parentId, ownerUserId)
                .orElseGet(() -> spaceType == SpaceType.SHARED
                        ? fileNodeRepository.findByIdAndSpaceTypeAndDeletedFalse(parentId, SpaceType.SHARED)
                                .orElse(null)
                        : null);
        if (parent == null) {
            throw new BusinessException(ErrorCode.FILE_NOT_FOUND, "父级文件夹不存在");
        }
        if (!NodeType.FOLDER.getValue().equals(parent.getNodeType())) {
            throw new BusinessException(ErrorCode.FILE_PATH_INVALID, "父级节点不是文件夹");
        }
        if (parent.getSpaceType() != spaceType) {
            throw new BusinessException(ErrorCode.FILE_PATH_INVALID, "父级目录与目标空间类型不一致");
        }
        return parent;
    }

    private static final int MAX_NAME_COLLISION_ITERATIONS = 1000;

    private String resolveAvailableName(UUID ownerUserId, SpaceType spaceType, UUID parentId, String requestedName) {
        String name = requestedName;
        int dotIndex = requestedName.lastIndexOf('.');
        String baseName = dotIndex <= 0 ? requestedName : requestedName.substring(0, dotIndex);
        String extension = dotIndex <= 0 ? "" : requestedName.substring(dotIndex);
        int index = 1;
        while (sameNameExists(ownerUserId, spaceType, parentId, name)) {
            if (index > MAX_NAME_COLLISION_ITERATIONS) {
                name = baseName + " (" + UUID.randomUUID().toString().substring(0, 8) + ")" + extension;
                break;
            }
            name = baseName + " (" + index + ")" + extension;
            index++;
        }
        return name;
    }

    private boolean sameNameExists(UUID ownerUserId, SpaceType spaceType, UUID parentId, String name) {
        if (spaceType == SpaceType.SHARED) {
            if (parentId == null) {
                return fileNodeRepository.existsBySpaceTypeAndParentIdIsNullAndNameAndDeletedFalse(spaceType, name);
            }
            return fileNodeRepository.existsBySpaceTypeAndParentIdAndNameAndDeletedFalse(spaceType, parentId, name);
        }
        if (parentId == null) {
            return fileNodeRepository.existsByOwnerUserIdAndSpaceTypeAndParentIdIsNullAndNameAndDeletedFalse(
                    ownerUserId, spaceType, name);
        }
        return fileNodeRepository.existsByOwnerUserIdAndSpaceTypeAndParentIdAndNameAndDeletedFalse(
                ownerUserId, spaceType, parentId, name);
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
