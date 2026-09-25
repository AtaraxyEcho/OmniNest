package com.omninest.worker.reader;

import com.omninest.common.error.StackSummaries;
import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.notification.port.NotificationPublisher;
import com.omninest.modules.reader.event.ComicParseTaskEvent;
import com.omninest.modules.reader.service.ReaderComicManifestService;
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
 * 漫画解析基础设施失败重试与超时恢复服务。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class ComicParseRetryService {

    private static final int MAX_RETRIES = 3;
    private static final String TASK_TYPE = "COMIC_PARSE";
    private static final String ERROR_CODE = "COMIC_PARSE_FAILED";

    private final TaskRecordService taskRecordService;
    private final TaskDispatchService taskDispatchService;
    private final ReaderComicManifestService manifestService;
    private final NotificationPublisher notificationPublisher;

    /**
     * 记录基础设施失败并按退避时间重新投递。
     *
     * @param event 原任务消息
     * @param exception 基础设施异常
     */
    @Transactional(rollbackFor = Exception.class)
    public void handleFailure(ComicParseTaskEvent event, Throwable exception) {
        int currentRetries = taskRecordService.retryCount(event.taskId());
        String errorSummary = exception.getClass().getSimpleName();
        if (currentRetries >= MAX_RETRIES) {
            if (!taskRecordService.markDeadLetter(event.taskId(), errorSummary, StackSummaries.summarize(exception))) {
                return;
            }
            markSourceFailed(event, errorSummary);
            notifyFailure(event, errorSummary);
            return;
        }
        Instant nextRetryAt = Instant.now().plus(retryDelay(currentRetries + 1));
        taskRecordService.markRetryWait(event.taskId(), errorSummary, nextRetryAt);
        taskDispatchService.enqueueAt(
                event.taskId(),
                QueueNames.TASK_EXCHANGE,
                QueueNames.COMIC_PARSE_ROUTING_KEY,
                retryEvent(event),
                nextRetryAt
        );
        log.warn("漫画解析任务等待重试: taskId={}, nextRetryAt={}, errorType={}",
                event.taskId(), nextRetryAt, errorSummary);
    }

    /**
     * 恢复心跳超时的漫画解析任务。
     *
     * @param taskId 任务 ID
     * @param heartbeatCutoff 心跳截止时间
     */
    @Transactional(rollbackFor = Exception.class)
    public void recoverStaleTask(UUID taskId, Instant heartbeatCutoff) {
        ComicParseTaskEvent event = eventFromPayload(taskId, taskRecordService.taskPayload(taskId));
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
            markSourceFailed(event, "WORKER_HEARTBEAT_TIMEOUT");
            notifyFailure(event, "WORKER_HEARTBEAT_TIMEOUT");
            return;
        }
        taskDispatchService.enqueueAt(
                taskId,
                QueueNames.TASK_EXCHANGE,
                QueueNames.COMIC_PARSE_ROUTING_KEY,
                retryEvent(event),
                recovery.nextRetryAt()
        );
    }

    private ComicParseTaskEvent eventFromPayload(UUID taskId, Map<String, Object> payload) {
        return new ComicParseTaskEvent(
                taskId,
                UUID.fromString(String.valueOf(payload.get("ownerUserId"))),
                UUID.fromString(String.valueOf(payload.get("itemId"))),
                UUID.fromString(String.valueOf(payload.get("sourceId"))),
                UUID.fromString(String.valueOf(payload.get("fileNodeId"))),
                String.valueOf(payload.get("fileFormat")),
                String.valueOf(payload.get("contentHash")),
                true
        );
    }

    private ComicParseTaskEvent retryEvent(ComicParseTaskEvent event) {
        return new ComicParseTaskEvent(
                event.taskId(),
                event.ownerUserId(),
                event.itemId(),
                event.sourceId(),
                event.fileNodeId(),
                event.fileFormat(),
                event.contentHash(),
                true
        );
    }

    private void markSourceFailed(ComicParseTaskEvent event, String errorSummary) {
        manifestService.markSourceFailed(
                event.itemId(),
                event.sourceId(),
                ERROR_CODE,
                "漫画解析失败，已进入死信队列: " + errorSummary
        );
    }

    private void notifyFailure(ComicParseTaskEvent event, String errorSummary) {
        notificationPublisher.notifyOrLog(
                event.ownerUserId(),
                "TASK_FAILED",
                "漫画解析失败",
                "漫画解析多次重试后仍未完成，请检查源文件后重新解析。",
                Map.of(
                        "taskId", event.taskId().toString(),
                        "itemId", event.itemId().toString(),
                        "sourceId", event.sourceId().toString(),
                        "errorCode", ERROR_CODE,
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
