package com.omninest.worker.photos;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.photos.event.PhotoAiEvent;
import com.omninest.modules.photos.event.PhotoAiEvent.Mode;
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
 * 照片图像分析任务的失败重试与心跳恢复服务。
 * 失败终态（死信）与等待重试的裁决依据任务记录的重试次数和错误类型；
 * 延迟重投通过任务 Outbox 按 nextRetryAt 发布，消息本体始终 ACK。
 * 任务依赖未就绪（如封面缩略图尚未回填）按专属短间隔阶梯重试，
 * 其余瞬态错误按默认 1 分钟、5 分钟、15 分钟阶梯重试。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class PhotoAiTaskRetryService {

    private static final int MAX_RETRIES = 3;

    private final TaskRecordService taskRecordService;
    private final TaskDispatchService taskDispatchService;

    /**
     * 处理照片图像分析任务失败。
     *
     * @param event 原任务事件
     * @param exception 执行异常
     */
    @Transactional(rollbackFor = Exception.class)
    public void handlePhotoAiFailure(PhotoAiEvent event, Throwable exception) {
        if (event == null || event.taskId() == null) {
            log.warn("旧版照片图像分析消息缺少任务标识，失败后不进入重试: photoId={}",
                    event == null ? null : event.photoId());
            return;
        }
        String errorSummary = errorSummary(exception);
        if (isNonRetryable(exception)) {
            taskRecordService.markDeadLetter(event.taskId(), errorSummary);
            log.warn("照片图像分析任务因业务错误进入死信终态: taskId={}, errorType={}",
                    event.taskId(), errorSummary);
            return;
        }

        int currentRetries = taskRecordService.retryCount(event.taskId());
        if (currentRetries >= MAX_RETRIES) {
            taskRecordService.markDeadLetter(event.taskId(), errorSummary);
            log.error("照片图像分析任务达到最大重试次数并进入死信: taskId={}, retryCount={}, errorType={}",
                    event.taskId(), currentRetries, errorSummary);
            return;
        }

        Instant nextRetryAt = Instant.now().plus(
                retryDelay(currentRetries + 1, isDependencyNotReady(exception)));
        int retryCount = taskRecordService.markRetryWait(event.taskId(), errorSummary, nextRetryAt);
        taskDispatchService.enqueueAt(
                event.taskId(),
                QueueNames.TASK_EXCHANGE,
                QueueNames.PHOTO_AI_ROUTING_KEY,
                event,
                nextRetryAt
        );
        log.warn("照片图像分析任务等待重试: taskId={}, retryCount={}, nextRetryAt={}, errorType={}",
                event.taskId(), retryCount, nextRetryAt, errorSummary);
    }

    /**
     * 恢复心跳超时的照片图像分析任务。
     *
     * @param taskId 任务 ID
     * @param taskType 任务类型
     * @param heartbeatCutoff 心跳截止时间
     */
    @Transactional(rollbackFor = Exception.class)
    public void recoverStaleTask(UUID taskId, String taskType, Instant heartbeatCutoff) {
        Map<String, Object> payload = taskRecordService.taskPayload(taskId);
        PhotoAiEvent event = rebuildEvent(taskId, payload);
        StaleTaskRecovery recovery = taskRecordService.recoverStaleTask(
                taskId,
                taskType,
                heartbeatCutoff,
                Instant.now(),
                "WORKER_HEARTBEAT_TIMEOUT"
        );
        if (recovery.recovered() && !recovery.deadLetter()) {
            taskDispatchService.enqueueAt(
                    taskId,
                    QueueNames.TASK_EXCHANGE,
                    QueueNames.PHOTO_AI_ROUTING_KEY,
                    event,
                    recovery.nextRetryAt()
            );
        }
    }

    private PhotoAiEvent rebuildEvent(UUID taskId, Map<String, Object> payload) {
        Mode mode = Mode.SINGLE_PHOTO;
        Object modeValue = payload.get("mode");
        if (modeValue != null) {
            try {
                mode = Mode.valueOf(String.valueOf(modeValue));
            } catch (IllegalArgumentException exception) {
                throw new BusinessException(ErrorCode.PARAM_ERROR, "照片图像分析任务载荷 mode 字段无效");
            }
        }
        UUID photoId = parseUuid(payload.get("photoId"));
        UUID ownerUserId = parseUuid(payload.get("ownerUserId"));
        if (ownerUserId == null) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "照片图像分析任务载荷缺少 ownerUserId");
        }
        return new PhotoAiEvent(taskId, ownerUserId, photoId, mode);
    }

    private UUID parseUuid(Object value) {
        if (value == null) {
            return null;
        }
        try {
            return UUID.fromString(String.valueOf(value));
        } catch (IllegalArgumentException exception) {
            return null;
        }
    }

    /**
     * 判断异常是否为任务依赖未就绪。
     * 该类失败的依赖通常很快恢复（如异步缩略图回填照片封面），
     * 不属于业务失败，按专属短间隔阶梯重试而非死信或默认长间隔。
     *
     * @param exception 执行异常
     * @return 是否依赖未就绪
     */
    public boolean isDependencyNotReady(Throwable exception) {
        return exception instanceof BusinessException businessException
                && businessException.errorCode() == ErrorCode.TASK_DEPENDENCY_NOT_READY;
    }

    private boolean isNonRetryable(Throwable exception) {
        if (!(exception instanceof BusinessException businessException)) {
            return false;
        }
        return switch (businessException.errorCode()) {
            case PARAM_ERROR, BAD_REQUEST, VALIDATION_FAILED, NOT_FOUND, TASK_NOT_FOUND,
                    FORBIDDEN, FILE_NOT_FOUND, FILE_LIFECYCLE_CONFLICT, RATE_LIMITED -> true;
            default -> false;
        };
    }

    private String errorSummary(Throwable exception) {
        return exception instanceof BusinessException businessException
                ? businessException.errorCode().name()
                : exception.getClass().getSimpleName();
    }

    private Duration retryDelay(int retryCount, boolean dependencyNotReady) {
        if (dependencyNotReady) {
            return switch (retryCount) {
                case 1 -> Duration.ofSeconds(10);
                case 2 -> Duration.ofSeconds(30);
                default -> Duration.ofMinutes(1);
            };
        }
        return switch (retryCount) {
            case 1 -> Duration.ofMinutes(1);
            case 2 -> Duration.ofMinutes(5);
            default -> Duration.ofMinutes(15);
        };
    }
}
