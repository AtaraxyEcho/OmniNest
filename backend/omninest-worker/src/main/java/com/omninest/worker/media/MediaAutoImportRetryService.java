package com.omninest.worker.media;

import com.omninest.common.error.StackSummaries;
import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.file.event.FileUploadedEvent;
import com.omninest.modules.file.event.MediaAutoImportRequestedEvent;
import com.omninest.modules.task.service.StaleTaskRecovery;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import java.time.Duration;
import java.time.Instant;
import java.util.Map;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 媒体自动导入失败重试服务。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class MediaAutoImportRetryService {
    private static final int MAX_RETRIES = 3;

    private final TaskRecordService taskRecordService;
    private final TaskDispatchService taskDispatchService;

    /**
     * 持久化失败状态并创建延迟 outbox。
     *
     * @param event 媒体自动导入任务消息
     * @param exception 执行异常
     */
    @Transactional(rollbackFor = Exception.class)
    public void handleFailure(MediaAutoImportRequestedEvent event, Throwable exception) {
        int currentRetries = taskRecordService.retryCount(event.taskId());
        String errorSummary = exception.getClass().getSimpleName();
        if (currentRetries >= MAX_RETRIES) {
            taskRecordService.markDeadLetter(event.taskId(), errorSummary, StackSummaries.summarize(exception));
            log.error("媒体自动导入任务进入死信终态: taskId={}, retryCount={}, errorType={}",
                    event.taskId(), currentRetries, errorSummary);
            return;
        }

        Instant nextRetryAt = Instant.now().plus(retryDelay(currentRetries + 1));
        int retryCount = taskRecordService.markRetryWait(event.taskId(), errorSummary, nextRetryAt);
        taskDispatchService.enqueueAt(
                event.taskId(),
                QueueNames.TASK_EXCHANGE,
                QueueNames.MEDIA_AUTO_IMPORT_ROUTING_KEY,
                event,
                nextRetryAt
        );
        log.warn("媒体自动导入任务等待重试: taskId={}, retryCount={}, nextRetryAt={}, errorType={}",
                event.taskId(), retryCount, nextRetryAt, errorSummary);
    }

    /**
     * 恢复心跳超时的媒体自动导入任务。
     *
     * @param taskId 任务 ID
     * @param heartbeatCutoff 心跳截止时间
     */
    @Transactional(rollbackFor = Exception.class)
    public void recoverStaleTask(UUID taskId, Instant heartbeatCutoff) {
        Map<String, Object> payload = taskRecordService.taskPayload(taskId);
        StaleTaskRecovery recovery = taskRecordService.recoverStaleTask(
                taskId,
                "MEDIA_AUTO_IMPORT",
                heartbeatCutoff,
                Instant.now(),
                "WORKER_HEARTBEAT_TIMEOUT"
        );
        if (!recovery.recovered() || recovery.deadLetter()) {
            return;
        }
        FileUploadedEvent file = new FileUploadedEvent(
                recovery.resourceId(),
                UUID.fromString(String.valueOf(payload.get("fileObjectId"))),
                recovery.ownerUserId(),
                "",
                "",
                String.valueOf(payload.get("fileName")),
                nullableString(payload.get("mimeType")),
                numberValue(payload.get("sizeBytes")),
                Instant.now()
        );
        taskDispatchService.enqueueAt(
                taskId,
                QueueNames.TASK_EXCHANGE,
                QueueNames.MEDIA_AUTO_IMPORT_ROUTING_KEY,
                new MediaAutoImportRequestedEvent(taskId, file),
                recovery.nextRetryAt()
        );
        log.warn("心跳超时的媒体自动导入任务已重新排队: taskId={}, retryCount={}, nextRetryAt={}",
                taskId, recovery.retryCount(), recovery.nextRetryAt());
    }

    private String nullableString(Object value) {
        String normalized = value == null ? null : String.valueOf(value);
        return normalized == null || normalized.isBlank() ? null : normalized;
    }

    private long numberValue(Object value) {
        if (value instanceof Number number) {
            return number.longValue();
        }
        return Long.parseLong(String.valueOf(value));
    }

    private Duration retryDelay(int retryCount) {
        return switch (retryCount) {
            case 1 -> Duration.ofMinutes(1);
            case 2 -> Duration.ofMinutes(5);
            default -> Duration.ofMinutes(15);
        };
    }
}
