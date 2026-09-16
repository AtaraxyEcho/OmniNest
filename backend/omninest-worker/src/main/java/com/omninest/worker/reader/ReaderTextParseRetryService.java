package com.omninest.worker.reader;

import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.notification.port.NotificationPublisher;
import com.omninest.modules.reader.event.ReaderParseTaskEvent;
import com.omninest.modules.reader.service.ReaderTextManifestService;
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
 * 文本书籍解析基础设施失败重试与超时恢复服务。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class ReaderTextParseRetryService {

    private static final int MAX_RETRIES = 3;
    private static final String TASK_TYPE = "READER_PARSE";

    private final TaskRecordService taskRecordService;
    private final TaskDispatchService taskDispatchService;
    private final ReaderTextManifestService manifestService;
    private final NotificationPublisher notificationPublisher;

    /**
     * 记录失败并按退避时间重新投递。
     *
     * @param event 原任务消息
     * @param exception 基础设施异常
     */
    @Transactional(rollbackFor = Exception.class)
    public void handleFailure(ReaderParseTaskEvent event, Throwable exception) {
        int currentRetries = taskRecordService.retryCount(event.taskId());
        String errorSummary = exception.getClass().getSimpleName();
        if (currentRetries >= MAX_RETRIES) {
            if (!taskRecordService.markDeadLetter(event.taskId(), errorSummary)) {
                return;
            }
            // 重试耗尽进入 DLQ 时回写条目失败状态并发布 READER 事件，
            // 避免书架卡片永久停留在"解析中"。
            manifestService.markFailed(
                    event.itemId(),
                    "READER_PARSE_FAILED",
                    "文本书籍解析失败，已进入死信队列: " + errorSummary
            );
            notifyFailure(event, errorSummary);
            return;
        }
        Instant nextRetryAt = Instant.now().plus(retryDelay(currentRetries + 1));
        taskRecordService.markRetryWait(event.taskId(), errorSummary, nextRetryAt);
        taskDispatchService.enqueueAt(
                event.taskId(),
                QueueNames.TASK_EXCHANGE,
                QueueNames.READER_PARSE_ROUTING_KEY,
                new ReaderParseTaskEvent(
                        event.taskId(),
                        event.ownerUserId(),
                        event.itemId(),
                        event.fileNodeId(),
                        event.fileFormat(),
                        event.contentHash(),
                        true
                ),
                nextRetryAt
        );
        log.warn("文本书籍解析任务等待重试: taskId={}, nextRetryAt={}, errorType={}",
                event.taskId(), nextRetryAt, errorSummary);
    }

    /**
     * 恢复心跳超时任务。
     *
     * @param taskId 任务 ID
     * @param heartbeatCutoff 心跳截止时间
     */
    @Transactional(rollbackFor = Exception.class)
    public void recoverStaleTask(UUID taskId, Instant heartbeatCutoff) {
        Map<String, Object> payload = taskRecordService.taskPayload(taskId);
        ReaderParseTaskEvent event = eventFromPayload(taskId, payload);
        StaleTaskRecovery recovery = taskRecordService.recoverStaleTask(
                taskId,
                TASK_TYPE,
                heartbeatCutoff,
                Instant.now(),
                "WORKER_HEARTBEAT_TIMEOUT"
        );
        if (!recovery.recovered()) {
            return;
        }
        if (recovery.deadLetter()) {
            manifestService.markFailed(
                    event.itemId(),
                    "READER_PARSE_FAILED",
                    "文本书籍解析失败，已进入死信队列: WORKER_HEARTBEAT_TIMEOUT"
            );
            notifyFailure(event, "WORKER_HEARTBEAT_TIMEOUT");
            return;
        }
        taskDispatchService.enqueueAt(
                taskId,
                QueueNames.TASK_EXCHANGE,
                QueueNames.READER_PARSE_ROUTING_KEY,
                event,
                recovery.nextRetryAt()
        );
    }

    private ReaderParseTaskEvent eventFromPayload(UUID taskId, Map<String, Object> payload) {
        return new ReaderParseTaskEvent(
                taskId,
                UUID.fromString(String.valueOf(payload.get("ownerUserId"))),
                UUID.fromString(String.valueOf(payload.get("itemId"))),
                UUID.fromString(String.valueOf(payload.get("fileNodeId"))),
                String.valueOf(payload.get("fileFormat")),
                String.valueOf(payload.get("contentHash")),
                true
        );
    }

    private void notifyFailure(ReaderParseTaskEvent event, String errorSummary) {
        notificationPublisher.notifyOrLog(
                event.ownerUserId(),
                "TASK_FAILED",
                "书籍解析失败",
                "书籍解析多次重试后仍未完成，请检查源文件后重新解析。",
                Map.of(
                        "taskId", event.taskId().toString(),
                        "itemId", event.itemId().toString(),
                        "errorCode", "READER_PARSE_FAILED",
                        "errorSummary", errorSummary
                )
        );
    }

    private Duration retryDelay(int retryCount) {
        return switch (retryCount) {
            case 1 -> Duration.ofMinutes(1);
            case 2 -> Duration.ofMinutes(5);
            default -> Duration.ofMinutes(15);
        };
    }
}
