package com.omninest.worker.photos;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.photos.event.PhotoGeoBackfillEvent;
import com.omninest.modules.photos.service.GeoDatasetService;
import com.omninest.modules.task.service.StaleTaskRecovery;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import java.time.Duration;
import java.time.Instant;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 照片位置回填任务的失败重试与心跳恢复服务。
 * 游标保存在任务 result 中，重试后自动续跑；延迟重投通过任务 Outbox 发布。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class PhotoGeoBackfillRetryService {

    private static final int MAX_RETRIES = 3;

    private final TaskRecordService taskRecordService;
    private final TaskDispatchService taskDispatchService;

    /**
     * 处理照片位置回填任务失败。
     *
     * @param event 原任务事件
     * @param exception 执行异常
     */
    @Transactional(rollbackFor = Exception.class)
    public void handleBackfillFailure(PhotoGeoBackfillEvent event, Throwable exception) {
        String errorSummary = errorSummary(exception);
        if (isNonRetryable(exception)) {
            taskRecordService.markDeadLetter(event.taskId(), errorSummary);
            log.warn("照片位置回填任务因业务错误进入死信终态: taskId={}, errorType={}",
                    event.taskId(), errorSummary);
            return;
        }
        int currentRetries = taskRecordService.retryCount(event.taskId());
        if (currentRetries >= MAX_RETRIES) {
            taskRecordService.markDeadLetter(event.taskId(), errorSummary);
            log.error("照片位置回填任务达到最大重试次数并进入死信: taskId={}, retryCount={}, errorType={}",
                    event.taskId(), currentRetries, errorSummary);
            return;
        }
        Instant nextRetryAt = Instant.now().plus(retryDelay(currentRetries + 1));
        int retryCount = taskRecordService.markRetryWait(event.taskId(), errorSummary, nextRetryAt);
        taskDispatchService.enqueueAt(
                event.taskId(),
                QueueNames.TASK_EXCHANGE,
                QueueNames.PHOTO_GEO_BACKFILL_ROUTING_KEY,
                rebuildBackfillEvent(event.taskId(), event),
                nextRetryAt
        );
        log.warn("照片位置回填任务等待重试: taskId={}, retryCount={}, nextRetryAt={}, errorType={}",
                event.taskId(), retryCount, nextRetryAt, errorSummary);
    }

    /**
     * 恢复心跳超时的照片位置回填任务。
     *
     * @param taskId 任务 ID
     * @param heartbeatCutoff 心跳截止时间
     */
    @Transactional(rollbackFor = Exception.class)
    public void recoverStaleTask(java.util.UUID taskId, Instant heartbeatCutoff) {
        PhotoGeoBackfillEvent event = rebuildBackfillEvent(taskId, null);
        StaleTaskRecovery recovery = taskRecordService.recoverStaleTask(
                taskId,
                GeoDatasetService.TASK_TYPE_BACKFILL,
                heartbeatCutoff,
                Instant.now(),
                "WORKER_HEARTBEAT_TIMEOUT"
        );
        if (recovery.recovered() && !recovery.deadLetter()) {
            taskDispatchService.enqueueAt(
                    taskId,
                    QueueNames.TASK_EXCHANGE,
                    QueueNames.PHOTO_GEO_BACKFILL_ROUTING_KEY,
                    event,
                    recovery.nextRetryAt()
            );
        }
    }

    private PhotoGeoBackfillEvent rebuildBackfillEvent(java.util.UUID taskId, PhotoGeoBackfillEvent fallback) {
        if (fallback != null) {
            return fallback;
        }
        var payload = taskRecordService.taskPayload(taskId);
        int batchSize = 200;
        Object batchSizeValue = payload.get("batchSize");
        if (batchSizeValue != null) {
            try {
                batchSize = Integer.parseInt(String.valueOf(batchSizeValue));
            } catch (NumberFormatException ignored) {
                // 载荷异常时回退默认批次大小。
            }
        }
        return new PhotoGeoBackfillEvent(taskId, batchSize, string(payload.get("datasetVersion")));
    }

    private boolean isNonRetryable(Throwable exception) {
        if (!(exception instanceof BusinessException businessException)) {
            return false;
        }
        return switch (businessException.errorCode()) {
            case PARAM_ERROR, VALIDATION_FAILED, NOT_FOUND, TASK_NOT_FOUND, FORBIDDEN -> true;
            default -> false;
        };
    }

    private String errorSummary(Throwable exception) {
        return exception instanceof BusinessException businessException
                ? businessException.errorCode().name()
                : exception.getClass().getSimpleName();
    }

    private Duration retryDelay(int retryCount) {
        return switch (retryCount) {
            case 1 -> Duration.ofMinutes(1);
            case 2 -> Duration.ofMinutes(5);
            default -> Duration.ofMinutes(15);
        };
    }

    private String string(Object value) {
        return value == null ? null : String.valueOf(value);
    }
}
