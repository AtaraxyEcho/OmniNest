package com.omninest.modules.video.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.error.StackSummaries;
import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import com.omninest.modules.video.event.LocalVideoLibraryApplyRequestedEvent;
import java.time.Duration;
import java.time.Instant;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** 本地媒体按需入库失败分类与延迟重试。 */
@Slf4j
@Service
@RequiredArgsConstructor
public class VideoLibraryApplyRetryService {
    private static final int MAX_RETRIES = 3;

    private final TaskRecordService taskRecordService;
    private final TaskDispatchService taskDispatchService;

    /** 根据异常类型结束任务或创建延迟重试 Outbox。 */
    @Transactional(rollbackFor = Exception.class)
    public void handleFailure(LocalVideoLibraryApplyRequestedEvent event, Throwable exception) {
        String errorSummary = errorSummary(exception);
        String stackSummary = StackSummaries.summarize(exception);
        if (!isRetryable(exception)) {
            taskRecordService.markFailed(event.taskId(), errorSummary, stackSummary);
            return;
        }
        int currentRetries = taskRecordService.retryCount(event.taskId());
        if (currentRetries >= MAX_RETRIES) {
            taskRecordService.markDeadLetter(event.taskId(), errorSummary, stackSummary);
            return;
        }
        Instant nextRetryAt = Instant.now().plus(retryDelay(currentRetries + 1));
        int retryCount = taskRecordService.markRetryWait(event.taskId(), errorSummary, nextRetryAt);
        taskDispatchService.enqueueAt(
                event.taskId(),
                QueueNames.TASK_EXCHANGE,
                QueueNames.LOCAL_VIDEO_LIBRARY_APPLY_ROUTING_KEY,
                event,
                nextRetryAt
        );
        log.warn(
                "本地媒体入库等待重试: taskId={}, retryCount={}, nextRetryAt={}, error={}",
                event.taskId(),
                retryCount,
                nextRetryAt,
                errorSummary
        );
    }

    private boolean isRetryable(Throwable exception) {
        if (exception instanceof BusinessException businessException) {
            return ErrorCode.DEPENDENCY_UNAVAILABLE.equals(businessException.errorCode())
                    || ErrorCode.INTERNAL_ERROR.equals(businessException.errorCode());
        }
        return true;
    }

    private String errorSummary(Throwable exception) {
        if (exception instanceof BusinessException businessException) {
            return businessException.errorCode().name();
        }
        return exception.getClass().getSimpleName();
    }

    private Duration retryDelay(int retryCount) {
        return switch (retryCount) {
            case 1 -> Duration.ofMinutes(1);
            case 2 -> Duration.ofMinutes(5);
            default -> Duration.ofMinutes(15);
        };
    }
}
