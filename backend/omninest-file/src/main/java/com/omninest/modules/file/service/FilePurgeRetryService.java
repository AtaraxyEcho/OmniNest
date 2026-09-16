package com.omninest.modules.file.service;

import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.file.domain.FilePurgeState;
import com.omninest.modules.file.event.FilePurgeRequestedEvent;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import com.omninest.modules.task.service.StaleTaskRecovery;
import java.time.Duration;
import java.time.Instant;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 文件永久删除失败和退避重试协调服务。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class FilePurgeRetryService {
    private static final int MAX_RETRIES = 3;

    private final TaskRecordService taskRecordService;
    private final TaskDispatchService taskDispatchService;
    private final FilePurgeStateService stateService;

    /**
     * 持久化失败状态并决定重试或进入死信终态。
     *
     * @param event 永久删除任务消息
     * @param exception 执行异常
     */
    @Transactional(rollbackFor = Exception.class)
    public void handleFailure(FilePurgeRequestedEvent event, Throwable exception) {
        int currentRetries = taskRecordService.retryCount(event.taskId());
        String errorSummary = exception.getClass().getSimpleName();
        if (currentRetries >= MAX_RETRIES) {
            taskRecordService.markDeadLetter(event.taskId(), errorSummary);
            stateService.updateNodeState(event.taskId(), FilePurgeState.FAILED);
            log.error("文件永久删除任务进入死信终态: taskId={}, retryCount={}, errorType={}",
                    event.taskId(), currentRetries, errorSummary);
            return;
        }
        Instant nextRetryAt = Instant.now().plus(retryDelay(currentRetries + 1));
        int retryCount = taskRecordService.markRetryWait(event.taskId(), errorSummary, nextRetryAt);
        stateService.updateNodeState(event.taskId(), FilePurgeState.RETRY_WAIT);
        taskDispatchService.enqueueAt(
                event.taskId(),
                QueueNames.TASK_EXCHANGE,
                QueueNames.FILE_PURGE_ROUTING_KEY,
                event,
                nextRetryAt
        );
        log.warn("文件永久删除任务等待重试: taskId={}, retryCount={}, nextRetryAt={}, errorType={}",
                event.taskId(), retryCount, nextRetryAt, errorSummary);
    }

    /**
     * 恢复心跳超时的文件永久删除任务。
     *
     * @param taskId 任务 ID
     * @param heartbeatCutoff 心跳截止时间
     */
    @Transactional(rollbackFor = Exception.class)
    public void recoverStaleTask(UUID taskId, Instant heartbeatCutoff) {
        Instant now = Instant.now();
        StaleTaskRecovery recovery = taskRecordService.recoverStaleTask(
                taskId,
                "FILE_PURGE",
                heartbeatCutoff,
                now,
                "WORKER_HEARTBEAT_TIMEOUT"
        );
        if (!recovery.recovered()) {
            return;
        }
        if (recovery.deadLetter()) {
            stateService.updateNodeState(taskId, FilePurgeState.FAILED);
            log.error("心跳超时的文件永久删除任务进入死信终态: taskId={}, retryCount={}",
                    taskId, recovery.retryCount());
            return;
        }
        FilePurgeRequestedEvent event = new FilePurgeRequestedEvent(
                taskId,
                recovery.ownerUserId(),
                recovery.resourceId()
        );
        stateService.updateNodeState(taskId, FilePurgeState.RETRY_WAIT);
        taskDispatchService.enqueueAt(
                taskId,
                QueueNames.TASK_EXCHANGE,
                QueueNames.FILE_PURGE_ROUTING_KEY,
                event,
                recovery.nextRetryAt()
        );
        log.warn("心跳超时的文件永久删除任务已重新排队: taskId={}, retryCount={}, nextRetryAt={}",
                taskId, recovery.retryCount(), recovery.nextRetryAt());
    }

    private Duration retryDelay(int retryCount) {
        return switch (retryCount) {
            case 1 -> Duration.ofMinutes(1);
            case 2 -> Duration.ofMinutes(5);
            default -> Duration.ofMinutes(15);
        };
    }
}
