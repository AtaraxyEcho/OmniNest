package com.omninest.modules.backdrop.service;

import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.backdrop.event.BackdropSecurityScanRequestedEvent;
import com.omninest.modules.task.domain.TaskRecord;
import com.omninest.modules.task.domain.TaskStatus;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 背景素材安全扫描任务的创建与 outbox 投递服务。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class BackdropScanTaskService {
    private static final String TASK_TYPE = "BACKDROP_SECURITY_SCAN";
    private static final String RESOURCE_TYPE = "BACKDROP_ASSET";
    private static final List<String> ACTIVE_STATUSES = List.of(
            TaskStatus.QUEUED.getValue(),
            TaskStatus.RUNNING.getValue(),
            TaskStatus.RETRY_WAIT.getValue()
    );

    private final TaskRecordService taskRecordService;
    private final TaskDispatchService taskDispatchService;

    /**
     * 在当前上传事务内创建安全扫描任务并写入 outbox。
     * 已有进行中的同资源任务时复用其任务 ID，保证重复提交幂等。
     *
     * @param ownerUserId 所属用户 ID
     * @param assetId 素材 ID
     * @param ingressItemId 入库记录 ID
     * @param originalFileName 暂存对象原始文件名
     * @return 扫描任务 ID
     */
    @Transactional(rollbackFor = Exception.class)
    public UUID enqueueScanTask(UUID ownerUserId, UUID assetId, UUID ingressItemId, String originalFileName) {
        Optional<TaskRecord> activeTask = taskRecordService.findActiveResourceTask(
                ownerUserId,
                TASK_TYPE,
                RESOURCE_TYPE,
                assetId,
                ACTIVE_STATUSES
        );
        if (activeTask.isPresent()) {
            return activeTask.get().getId();
        }
        UUID taskId = UUID.randomUUID();
        Map<String, Object> payload = Map.of(
                "assetId", assetId.toString(),
                "ingressItemId", ingressItemId.toString(),
                "originalFileName", originalFileName == null ? "" : originalFileName
        );
        taskRecordService.createQueuedTask(
                taskId,
                ownerUserId,
                TASK_TYPE,
                QueueNames.BACKDROP_SECURITY_SCAN_ROUTING_KEY,
                "PENDING",
                RESOURCE_TYPE,
                assetId,
                payload
        );
        taskDispatchService.enqueue(
                taskId,
                QueueNames.TASK_EXCHANGE,
                QueueNames.BACKDROP_SECURITY_SCAN_ROUTING_KEY,
                new BackdropSecurityScanRequestedEvent(taskId, ownerUserId, assetId, ingressItemId, originalFileName)
        );
        return taskId;
    }

    /**
     * 判断素材是否存在进行中的安全扫描任务（对账守卫使用）。
     *
     * @param ownerUserId 所属用户 ID
     * @param assetId 素材 ID
     * @return 存在进行中任务时返回 true
     */
    public boolean hasActiveScanTask(UUID ownerUserId, UUID assetId) {
        return taskRecordService.findActiveResourceTask(
                ownerUserId,
                TASK_TYPE,
                RESOURCE_TYPE,
                assetId,
                ACTIVE_STATUSES
        ).isPresent();
    }
}
