package com.omninest.modules.file.service;

import com.omninest.common.download.OfflineDownloadSourceResolver;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.file.domain.DownloadOfflineTask;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.NodeType;
import com.omninest.modules.file.dto.CreateOfflineDownloadRequest;
import com.omninest.modules.file.dto.OfflineDownloadTaskDto;
import com.omninest.modules.file.event.OfflineDownloadRequestedEvent;
import com.omninest.modules.file.repository.DownloadOfflineTaskRepository;
import com.omninest.modules.file.repository.FileNodeRepository;
import com.omninest.modules.task.domain.TaskStatus;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 管理离线下载请求、任务状态和任务消息发布。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class OfflineDownloadRequestService {

    private final DownloadOfflineTaskRepository offlineTaskRepository;
    private final FileNodeRepository fileNodeRepository;
    private final OfflineDownloadSourceResolver sourceResolver;
    private final TaskRecordService taskRecordService;
    private final TaskDispatchService taskDispatchService;

    /**
     * 查询用户的离线下载任务。
     *
     * @param ownerUserId 所有者用户 ID
     * @return 按创建时间倒序排列的任务
     */
    @Transactional(readOnly = true)
    public List<OfflineDownloadTaskDto> listTasks(UUID ownerUserId) {
        return offlineTaskRepository.findByOwnerUserIdOrderByCreatedAtDesc(ownerUserId)
                .stream()
                .map(this::toDto)
                .toList();
    }

    /**
     * 创建离线下载任务并在事务提交后发布执行消息。
     *
     * @param ownerUserId 所有者用户 ID
     * @param request 下载请求
     * @return 已创建的任务
     */
    @Transactional(rollbackFor = Exception.class)
    public OfflineDownloadTaskDto createTask(UUID ownerUserId, CreateOfflineDownloadRequest request) {
        sourceResolver.resolve(request.sourceUri());
        FileNode parent = resolveParent(ownerUserId, request.targetParentId());
        UUID taskId = UUID.randomUUID();
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("sourceUri", request.sourceUri().trim());
        payload.put("targetParentId", parent == null ? null : parent.getId().toString());
        taskRecordService.createQueuedTask(
                taskId,
                ownerUserId,
                "OFFLINE_DOWNLOAD",
                QueueNames.OFFLINE_DOWNLOAD_ROUTING_KEY,
                payload
        );

        DownloadOfflineTask task = new DownloadOfflineTask();
        task.setId(taskId);
        task.setOwnerUserId(ownerUserId);
        task.setSourceUri(request.sourceUri().trim());
        task.setTargetParentId(parent == null ? null : parent.getId());
        task.setTaskId(taskId);
        task.setStatus(TaskStatus.QUEUED.getValue());
        DownloadOfflineTask saved = offlineTaskRepository.save(task);
        log.info("创建离线下载任务: taskId={}, ownerUserId={}", taskId, ownerUserId);
        OfflineDownloadRequestedEvent event = new OfflineDownloadRequestedEvent(saved.getId());
        // 任务记录与 Outbox 投递行在同一事务提交，避免"记录已建而消息丢失"的僵尸任务。
        taskDispatchService.enqueue(
                taskId,
                QueueNames.TASK_EXCHANGE,
                QueueNames.OFFLINE_DOWNLOAD_ROUTING_KEY,
                event
        );
        return toDto(saved);
    }

    /**
     * 取消尚未结束的离线下载任务。
     *
     * @param ownerUserId 所有者用户 ID
     * @param taskId 离线下载任务 ID
     */
    @Transactional(rollbackFor = Exception.class)
    public void cancelTask(UUID ownerUserId, UUID taskId) {
        DownloadOfflineTask task = offlineTaskRepository.findByIdAndOwnerUserId(taskId, ownerUserId)
                .orElseThrow(() -> new BusinessException(ErrorCode.TASK_NOT_FOUND, "离线下载任务不存在"));
        if (isTerminal(task.getStatus())) {
            return;
        }
        task.setStatus(TaskStatus.CANCELLED.getValue());
        offlineTaskRepository.save(task);
        taskRecordService.markCancelled(resolveSystemTaskId(task));
        log.info("取消离线下载任务: taskId={}, ownerUserId={}", taskId, ownerUserId);
    }

    private FileNode resolveParent(UUID ownerUserId, UUID parentId) {
        if (parentId == null) {
            return null;
        }
        FileNode parent = fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(parentId, ownerUserId)
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "目标文件夹不存在"));
        if (!NodeType.FOLDER.getValue().equals(parent.getNodeType())) {
            throw new BusinessException(ErrorCode.FILE_PATH_INVALID, "目标父级必须是文件夹");
        }
        return parent;
    }

    private boolean isTerminal(String status) {
        return List.of(
                TaskStatus.COMPLETED.getValue(),
                TaskStatus.FAILED.getValue(),
                TaskStatus.CANCELLED.getValue()
        ).contains(status);
    }

    private UUID resolveSystemTaskId(DownloadOfflineTask task) {
        return task.getTaskId() == null ? task.getId() : task.getTaskId();
    }

    private OfflineDownloadTaskDto toDto(DownloadOfflineTask task) {
        return new OfflineDownloadTaskDto(
                task.getId(),
                task.getSourceUri(),
                task.getTargetParentId(),
                task.getTaskId(),
                task.getStatus(),
                task.getAria2Gid(),
                task.getFileName(),
                task.getTotalBytes(),
                task.getCompletedBytes(),
                task.getDownloadSpeedBytes(),
                task.getErrorSummary(),
                task.getCompletedFileId(),
                task.getCompletedAt(),
                task.getCreatedAt(),
                task.getUpdatedAt()
        );
    }
}
