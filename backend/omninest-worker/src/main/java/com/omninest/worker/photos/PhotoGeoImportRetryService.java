package com.omninest.worker.photos;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.error.StackSummaries;
import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.photos.event.PhotoGeoImportEvent;
import com.omninest.modules.photos.service.GeoDatasetService;
import com.omninest.modules.photos.service.GeonamesImportService;
import com.omninest.modules.task.service.StaleTaskRecovery;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import java.time.Duration;
import java.time.Instant;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 照片 GeoNames 导入任务的失败重试与心跳恢复服务。
 * 阶段状态保存在任务 phase 中，重试从失败阶段继续；延迟重投通过任务 Outbox 发布。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class PhotoGeoImportRetryService {

    private static final int MAX_RETRIES = 3;

    private final TaskRecordService taskRecordService;
    private final TaskDispatchService taskDispatchService;

    /**
     * 处理 GeoNames 导入任务失败。
     *
     * @param event 原任务事件
     * @param exception 执行异常
     */
    @Transactional(rollbackFor = Exception.class)
    public void handleImportFailure(PhotoGeoImportEvent event, Throwable exception) {
        handleFailure(event.taskId(), exception, () -> rebuildImportEvent(event.taskId()));
    }

    /**
     * 恢复心跳超时的 GeoNames 导入任务。
     *
     * @param taskId 任务 ID
     * @param heartbeatCutoff 心跳截止时间
     */
    @Transactional(rollbackFor = Exception.class)
    public void recoverStaleTask(UUID taskId, Instant heartbeatCutoff) {
        PhotoGeoImportEvent event = rebuildImportEvent(taskId);
        StaleTaskRecovery recovery = taskRecordService.recoverStaleTask(
                taskId,
                GeoDatasetService.TASK_TYPE_IMPORT,
                heartbeatCutoff,
                Instant.now(),
                "WORKER_HEARTBEAT_TIMEOUT"
        );
        if (recovery.recovered() && !recovery.deadLetter()) {
            taskDispatchService.enqueueAt(
                    taskId,
                    QueueNames.TASK_EXCHANGE,
                    QueueNames.PHOTO_GEO_IMPORT_ROUTING_KEY,
                    event,
                    recovery.nextRetryAt()
            );
        }
    }

    private void handleFailure(UUID taskId, Throwable exception, EventSupplier eventSupplier) {
        String errorSummary = errorSummary(exception);
        String stackSummary = StackSummaries.summarize(exception);
        if (isNonRetryable(exception)) {
            taskRecordService.markDeadLetter(taskId, errorSummary, stackSummary);
            log.warn("GeoNames 任务因业务错误进入死信终态: taskId={}, errorType={}", taskId, errorSummary);
            return;
        }
        int currentRetries = taskRecordService.retryCount(taskId);
        if (currentRetries >= MAX_RETRIES) {
            taskRecordService.markDeadLetter(taskId, errorSummary, stackSummary);
            log.error("GeoNames 任务达到最大重试次数并进入死信: taskId={}, retryCount={}, errorType={}",
                    taskId, currentRetries, errorSummary);
            return;
        }
        Instant nextRetryAt = Instant.now().plus(retryDelay(currentRetries + 1));
        int retryCount = taskRecordService.markRetryWait(taskId, errorSummary, nextRetryAt);
        taskDispatchService.enqueueAt(
                taskId,
                QueueNames.TASK_EXCHANGE,
                QueueNames.PHOTO_GEO_IMPORT_ROUTING_KEY,
                eventSupplier.get(),
                nextRetryAt
        );
        log.warn("GeoNames 任务等待重试: taskId={}, retryCount={}, nextRetryAt={}, errorType={}",
                taskId, retryCount, nextRetryAt, errorSummary);
    }

    private PhotoGeoImportEvent rebuildImportEvent(UUID taskId) {
        var payload = taskRecordService.taskPayload(taskId);
        UUID datasetId = parseUuid(payload.get("datasetId"));
        if (datasetId == null) {
            throw new IllegalArgumentException("导入任务载荷缺少 datasetId");
        }
        return new PhotoGeoImportEvent(
                taskId,
                datasetId,
                string(payload.get("datasetVersion")),
                string(payload.get("dumpDate"))
        );
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

    private UUID parseUuid(Object value) {
        try {
            return value == null ? null : UUID.fromString(String.valueOf(value));
        } catch (IllegalArgumentException ex) {
            return null;
        }
    }

    private String string(Object value) {
        return value == null ? null : String.valueOf(value);
    }

    /** 延迟重投事件的惰性构建器：仅在确定重试时才读取任务载荷。 */
    @FunctionalInterface
    private interface EventSupplier {

        /**
         * @return 重投事件
         */
        Object get();
    }
}
