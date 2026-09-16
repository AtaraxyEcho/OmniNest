package com.omninest.modules.file.service;

import com.alibaba.fastjson2.JSON;
import com.alibaba.fastjson2.JSONObject;
import com.omninest.common.error.BusinessException;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.messaging.QueueNames;
import com.omninest.common.rclone.RcloneGateway;
import com.omninest.modules.file.config.ExternalStorageImportProperties;
import com.omninest.modules.file.domain.ExternalStorageStatus;
import com.omninest.modules.file.domain.ImportSourceKind;
import com.omninest.modules.file.domain.ImportTaskStatus;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.domain.StorageExternalAccount;
import com.omninest.modules.file.domain.StorageImportTask;
import com.omninest.modules.file.dto.CreateImportTaskRequest;
import com.omninest.modules.file.dto.ExternalFileItemDto;
import com.omninest.modules.file.dto.ExternalFileListDto;
import com.omninest.modules.file.dto.ExternalSpaceDto;
import com.omninest.modules.file.dto.ImportTaskDto;
import com.omninest.modules.file.event.ExternalImportRequestedEvent;
import com.omninest.modules.file.repository.StorageExternalAccountRepository;
import com.omninest.modules.file.repository.StorageImportTaskRepository;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 外部存储核心服务。
 * <p>
 * 管理 rclone remote 生命周期，提供浏览、文件操作和导入任务管理。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class ExternalStorageService {
    private final RcloneGateway rcloneGateway;
    private final StorageExternalAccountRepository accountRepository;
    private final StorageImportTaskRepository importTaskRepository;
    private final TaskDispatchService taskDispatchService;
    private final TaskRecordService taskRecordService;
    private final ExternalStorageCredentialService externalStorageCredentialService;
    private final SharedSpaceService sharedSpaceService;
    private final ExternalStorageImportProperties importProperties;

    // ========== Remote 生命周期 ==========

    /**
     * 激活外部存储 remote：解密凭证 → rclone config/create。
     */
    public void activateRemote(StorageExternalAccount account) {
        String remoteName = toRemoteName(account);
        Map<String, String> params = decryptCredentials(account);
        String rcloneType = toRcloneType(account.getProvider());
        rcloneGateway.createRemote(remoteName, rcloneType, params);
        log.info("外部存储 remote 已激活: accountId={}", account.getId());
    }

    /**
     * 停用外部存储 remote：rclone config/delete。
     */
    public void deactivateRemote(StorageExternalAccount account) {
        String remoteName = toRemoteName(account);
        try {
            rcloneGateway.deleteRemote(remoteName);
            log.info("外部存储 remote 已停用: accountId={}", account.getId());
        } catch (Exception e) {
            log.warn("停用 remote 失败（可能已不存在）: accountId={}", account.getId(), e);
        }
    }

    // ========== 浏览 ==========

    /**
     * 浏览外部存储目录。
     * DB 查询在 findAccount 内完成，rclone 网络 IO 在事务外执行。
     */
    public ExternalFileListDto browse(UUID ownerUserId, UUID accountId, String path) {
        StorageExternalAccount account = findAccount(ownerUserId, accountId);
        ensureActive(account);
        String fs = resolveFs(account);
        String remote = normalizePath(path);

        ensureRemoteActivated(account);

        try {
            List<ExternalFileItemDto> items = rcloneGateway.listDirectory(fs, remote, false).stream()
                    .map(entry -> new ExternalFileItemDto(
                            entry.name(),
                            entry.name(),
                            entry.directory(),
                            entry.sizeBytes(),
                            entry.modifiedAt(),
                            entry.mimeType(),
                            entry.hash()
                    ))
                    .toList();
            return new ExternalFileListDto(items, path);
        } catch (IllegalStateException e) {
            String message = e.getMessage();
            if (message != null && message.contains("directory not found")) {
                log.warn("远程目录不存在: accountId={}", accountId);
                return new ExternalFileListDto(List.of(), path);
            }
            throw e;
        }
    }

    /**
     * 获取外部存储空间使用情况。
     * DB 查询在 findAccount 内完成，rclone 网络 IO 在事务外执行。
     */
    public ExternalSpaceDto getSpaceUsage(UUID ownerUserId, UUID accountId) {
        StorageExternalAccount account = findAccount(ownerUserId, accountId);
        ensureActive(account);
        String fs = resolveFs(account);

        ensureRemoteActivated(account);

        RcloneGateway.SpaceUsage usage = rcloneGateway.querySpaceUsage(fs);
        return new ExternalSpaceDto(
                usage.totalBytes(),
                usage.usedBytes(),
                usage.freeBytes(),
                usage.trashedBytes()
        );
    }

    /**
     * 获取 remote 文件系统信息。
     * DB 查询在 findAccount 内完成，rclone 网络 IO 在事务外执行。
     */
    public Map<String, Object> getFsInfo(UUID ownerUserId, UUID accountId) {
        StorageExternalAccount account = findAccount(ownerUserId, accountId);
        ensureActive(account);
        String fs = resolveFs(account);

        ensureRemoteActivated(account);

        return rcloneGateway.queryFileSystemInfo(fs);
    }

    // ========== 导入任务 ==========

    /**
     * 创建导入任务：外部存储 → MinIO。
     *
     * @param ownerUserId 当前用户 ID
     * @param accountId 外部存储账户 ID
     * @param request 导入任务请求
     * @return 已创建的导入任务
     */
    @Transactional(rollbackFor = Exception.class)
    public ImportTaskDto createImportTask(UUID ownerUserId, UUID accountId, CreateImportTaskRequest request) {
        StorageExternalAccount account = findAccount(ownerUserId, accountId);
        ensureActive(account);

        String fileName = extractFileName(request.sourcePath());
        SpaceType resolvedSpace = resolveSpaceType(request.spaceType());
        String spaceType = resolvedSpace.getValue();
        String sourceKind = resolveSourceKind(request.sourceKind()).getValue();
        ensureImportTargetAllowed(ownerUserId, resolvedSpace);
        ensureImportSizeWithinGuard(request);
        UUID systemTaskId = UUID.randomUUID();
        StorageImportTask task = new StorageImportTask();
        task.setId(UUID.randomUUID());
        task.setTaskId(systemTaskId);
        task.setOwnerUserId(ownerUserId);
        task.setExternalAccountId(accountId);
        task.setSourcePath(request.sourcePath());
        task.setSourceKind(sourceKind);
        task.setTargetParentId(request.targetParentId());
        task.setSpaceType(spaceType);
        task.setFileName(fileName);
        task.setStatus(ImportTaskStatus.QUEUED.getValue());
        taskRecordService.createQueuedTask(
                systemTaskId,
                ownerUserId,
                "EXTERNAL_IMPORT",
                QueueNames.EXTERNAL_IMPORT_ROUTING_KEY,
                Map.of(
                        "importTaskId", task.getId().toString(),
                        "externalAccountId", accountId.toString(),
                        "sourcePath", request.sourcePath(),
                        "sourceKind", sourceKind,
                        "targetParentId", request.targetParentId() == null ? "" : request.targetParentId().toString(),
                        "spaceType", spaceType
                )
        );
        StorageImportTask saved = importTaskRepository.save(task);

        // 任务记录与 Outbox 投递行在同一事务提交，避免"记录已建而消息丢失"的僵尸任务。
        taskDispatchService.enqueue(
                systemTaskId,
                QueueNames.TASK_EXCHANGE,
                QueueNames.EXTERNAL_IMPORT_ROUTING_KEY,
                new ExternalImportRequestedEvent(saved.getId())
        );
        log.info("外部存储导入任务已提交: taskId={}", saved.getId());

        return toImportTaskDto(saved);
    }

    /**
     * 列出用户的导入任务。
     */
    @Transactional(readOnly = true)
    public List<ImportTaskDto> listImportTasks(UUID ownerUserId) {
        return importTaskRepository.findByOwnerUserIdOrderByCreatedAtDesc(ownerUserId)
                .stream()
                .map(this::toImportTaskDto)
                .toList();
    }

    /**
     * 取消或删除导入任务。
     * <p>
     * 运行中的任务：取消执行并标记为 CANCELLED。
     * 已结束的任务（COMPLETED / FAILED / CANCELLED）：从数据库中删除记录。
     */
    @Transactional(rollbackFor = Exception.class)
    public void cancelImportTask(UUID ownerUserId, UUID taskId) {
        StorageImportTask task = importTaskRepository.findByIdAndOwnerUserId(taskId, ownerUserId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "导入任务不存在"));

        String status = task.getStatus();
        boolean isFinished = ImportTaskStatus.COMPLETED.getValue().equals(status)
                || ImportTaskStatus.FAILED.getValue().equals(status)
                || ImportTaskStatus.CANCELLED.getValue().equals(status);

        if (isFinished) {
            importTaskRepository.delete(task);
            log.info("导入任务已删除: taskId={}", taskId);
            return;
        }

        // 如果 rclone job 正在运行，停止它
        if (task.getRcloneJobId() != null && ImportTaskStatus.RUNNING.getValue().equals(status)) {
            try {
                rcloneGateway.stopJob(task.getRcloneJobId());
            } catch (Exception e) {
                log.warn("停止 rclone job 失败: jobId={}", task.getRcloneJobId(), e);
            }
        }

        task.setStatus(ImportTaskStatus.CANCELLED.getValue());
        importTaskRepository.save(task);
        taskRecordService.markCancelled(systemTaskId(task));
        log.info("导入任务已取消: taskId={}", taskId);
    }

    // ========== 内部方法 ==========

    /**
     * 确保 rclone remote 已创建。如果尚未激活则自动激活。
     */
    private void ensureRemoteActivated(StorageExternalAccount account) {
        String remoteName = toRemoteName(account);
        try {
            List<String> remotes = rcloneGateway.listRemoteNames();
            if (remotes.contains(remoteName)) {
                return;
            }
        } catch (Exception e) {
            log.warn("检查 remote 列表失败，尝试重新激活: {}", remoteName, e);
        }
        activateRemote(account);
    }

    /**
     * 根据 account ID 生成 rclone remote 名称。
     */
    String toRemoteName(StorageExternalAccount account) {
        return "omni-" + account.getId().toString().replace("-", "").substring(0, 8);
    }

    /**
     * 解析 rclone 文件系统标识。
     */
    String resolveFs(StorageExternalAccount account) {
        return toRemoteName(account) + ":";
    }

    /**
     * 解密外部存储凭证，返回 rclone 参数 map。
     */
    @SuppressWarnings("unchecked")
    private Map<String, String> decryptCredentials(StorageExternalAccount account) {
        String plaintextJson = externalStorageCredentialService.decryptToJson(account.getEncryptedCredentials());
        try {
            JSONObject json = JSON.parseObject(plaintextJson);
            return json.entrySet().stream()
                    .collect(Collectors.toMap(
                            Map.Entry::getKey,
                            e -> e.getValue() == null ? "" : e.getValue().toString()
                    ));
        } catch (Exception e) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "凭证格式无效，无法解析");
        }
    }

    /**
     * 将 OmniNest provider 名映射为 rclone type。
     */
    private String toRcloneType(String provider) {
        return switch (provider.toUpperCase()) {
            case "S3", "MINIO" -> "s3";
            case "WEBDAV" -> "webdav";
            case "ONEDRIVE" -> "onedrive";
            case "GDRIVE", "GOOGLE_DRIVE" -> "drive";
            case "ALIYUN_DRIVE" -> "alipan";
            case "DROPBOX" -> "dropbox";
            default -> throw new BusinessException(ErrorCode.PARAM_ERROR, "不支持的外部存储类型");
        };
    }

    private void ensureImportTargetAllowed(UUID ownerUserId, SpaceType spaceType) {
        if (spaceType == SpaceType.SHARED) {
            sharedSpaceService.requireSharedWrite(ownerUserId);
        }
    }

    private void ensureImportSizeWithinGuard(CreateImportTaskRequest request) {
        // 体积在 Worker 获知 totalSize 后由 ensureImportBytesAllowed / ensureSingleFileAllowed 校验。
    }

    /**
     * 按体积阈值拒绝导入（Worker 侧在获知 totalSize 后调用）。
     *
     * @param totalBytes 预估或实际总字节
     */
    public void ensureImportBytesAllowed(long totalBytes) {
        long maxTotal = importProperties.getMaxTotalBytes();
        if (maxTotal > 0 && totalBytes > maxTotal) {
            throw new BusinessException(ErrorCode.PARAM_ERROR,
                    "导入总量超过限制，请改用本地媒体目录或减小导入范围");
        }
    }

    /**
     * 拒绝超大单文件导入。
     *
     * @param fileBytes 单文件字节数
     */
    public void ensureSingleFileAllowed(long fileBytes) {
        long maxFile = importProperties.getMaxFileBytes();
        if (maxFile > 0 && fileBytes > maxFile) {
            throw new BusinessException(ErrorCode.PARAM_ERROR,
                    "单文件超过导入大小限制，请将大体积内容放入本地媒体目录");
        }
    }

    private StorageExternalAccount findAccount(UUID ownerUserId, UUID accountId) {
        return accountRepository.findByIdAndOwnerUserId(accountId, ownerUserId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "外部存储账户不存在"));
    }

    private void ensureActive(StorageExternalAccount account) {
        if (!ExternalStorageStatus.ACTIVE.getValue().equals(account.getStatus())) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "外部存储账户已禁用");
        }
    }

    private String normalizePath(String path) {
        if (path == null || path.isBlank() || path.equals("/")) {
            return "";
        }
        String normalized = path.startsWith("/") ? path.substring(1) : path;
        normalized = normalized.endsWith("/") ? normalized.substring(0, normalized.length() - 1) : normalized;
        if (normalized.contains("..")) {
            throw new BusinessException(ErrorCode.FILE_PATH_INVALID, "路径不允许包含 ..");
        }
        return normalized;
    }

    private String extractFileName(String sourcePath) {
        String normalized = normalizePath(sourcePath);
        int lastSlash = normalized.lastIndexOf('/');
        return lastSlash < 0 ? normalized : normalized.substring(lastSlash + 1);
    }

    private ImportTaskDto toImportTaskDto(StorageImportTask task) {
        return new ImportTaskDto(
                task.getId(),
                task.getTaskId(),
                task.getExternalAccountId(),
                task.getSourcePath(),
                task.getSourceKind(),
                task.getFileName(),
                task.getTotalBytes(),
                task.getTransferredBytes(),
                task.getSpeedBytes(),
                task.getTotalFiles(),
                task.getCompletedFiles(),
                task.getCurrentFileName(),
                task.getStatus(),
                task.getErrorSummary(),
                task.getCompletedFileId(),
                task.getCreatedAt(),
                task.getUpdatedAt()
        );
    }

    private ImportSourceKind resolveSourceKind(String sourceKind) {
        try {
            return ImportSourceKind.fromValue(
                    sourceKind == null || sourceKind.isBlank()
                            ? ImportSourceKind.FILE.getValue()
                            : sourceKind
            );
        } catch (IllegalArgumentException exception) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "导入源类型不合法");
        }
    }

    private SpaceType resolveSpaceType(String spaceType) {
        try {
            return SpaceType.fromValue(
                    spaceType == null || spaceType.isBlank()
                            ? SpaceType.PERSONAL.getValue()
                            : spaceType
            );
        } catch (IllegalArgumentException exception) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "空间类型不合法");
        }
    }

    private UUID systemTaskId(StorageImportTask task) {
        return task.getTaskId() == null ? task.getId() : task.getTaskId();
    }
}
