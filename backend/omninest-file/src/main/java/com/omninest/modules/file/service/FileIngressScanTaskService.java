package com.omninest.modules.file.service;

import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.file.event.FileSecurityScanRequestedEvent;
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
 * 文件安全扫描任务的创建与 outbox 投递服务。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class FileIngressScanTaskService {
    private static final String TASK_TYPE = "FILE_SECURITY_SCAN";
    private static final String RESOURCE_TYPE = "FILE_INGRESS";
    private static final List<String> ACTIVE_STATUSES = List.of(
            TaskStatus.QUEUED.getValue(),
            TaskStatus.RUNNING.getValue(),
            TaskStatus.RETRY_WAIT.getValue()
    );

    private final TaskRecordService taskRecordService;
    private final TaskDispatchService taskDispatchService;

    /**
     * 在当前上传事务内创建安全扫描任务并写入 outbox。
     * 已有进行中的同资源任务时复用其任务 ID，保证重复完成请求幂等。
     *
     * @param ownerUserId 所属用户 ID
     * @param ingressItemId 安全入库记录 ID
     * @param asVersionOfFileId 版本上传目标节点 ID，可为空
     * @param declaredSha256 客户端声明摘要，可为空
     * @return 扫描任务 ID
     */
    @Transactional(rollbackFor = Exception.class)
    public UUID enqueueScanTask(
            UUID ownerUserId,
            UUID ingressItemId,
            UUID asVersionOfFileId,
            String declaredSha256
    ) {
        Optional<TaskRecord> activeTask = taskRecordService.findActiveResourceTask(
                ownerUserId,
                TASK_TYPE,
                RESOURCE_TYPE,
                ingressItemId,
                ACTIVE_STATUSES
        );
        if (activeTask.isPresent()) {
            return activeTask.get().getId();
        }
        UUID taskId = UUID.randomUUID();
        Map<String, Object> payload = Map.of(
                "ingressItemId", ingressItemId.toString(),
                "asVersionOfFileId", asVersionOfFileId == null ? "" : asVersionOfFileId.toString(),
                "declaredSha256", declaredSha256 == null ? "" : declaredSha256
        );
        taskRecordService.createQueuedTask(
                taskId,
                ownerUserId,
                TASK_TYPE,
                QueueNames.FILE_SECURITY_SCAN_ROUTING_KEY,
                "PENDING",
                RESOURCE_TYPE,
                ingressItemId,
                payload
        );
        taskDispatchService.enqueue(
                taskId,
                QueueNames.TASK_EXCHANGE,
                QueueNames.FILE_SECURITY_SCAN_ROUTING_KEY,
                new FileSecurityScanRequestedEvent(
                        taskId,
                        ownerUserId,
                        ingressItemId,
                        asVersionOfFileId,
                        declaredSha256
                )
        );
        return taskId;
    }
}
