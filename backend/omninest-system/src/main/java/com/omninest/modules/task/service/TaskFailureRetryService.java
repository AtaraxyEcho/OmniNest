package com.omninest.modules.task.service;

import com.omninest.common.error.StackSummaries;
import com.omninest.common.messaging.QueueNames;
import java.time.Instant;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Worker 消费失败的统一重试与死信裁决服务。
 *
 * <p>按 1 分钟、5 分钟、15 分钟退避重试，最多 3 次；耗尽后转入 DLQ。
 * 执行体负责落业务终态，本服务只维护系统任务状态并调度下一次投递。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class TaskFailureRetryService {
    private static final int MAX_ERROR_LENGTH = 500;

    private final TaskRecordService taskRecordService;
    private final TaskDispatchService taskDispatchService;

    /**
     * 根据任务当前重试次数决定重新排队或进入死信。
     *
     * @param taskId 任务 ID
     * @param routingKey 消息路由键
     * @param event 原始任务消息
     * @param exception 执行异常
     * @return 裁决结果
     */
    @Transactional(rollbackFor = Exception.class)
    public FailureOutcome handleFailure(UUID taskId, String routingKey, Object event, Throwable exception) {
        String errorSummary = errorSummary(exception);
        FailureResolution resolution = taskRecordService.resolveFailure(
                taskId,
                errorSummary,
                StackSummaries.summarize(exception),
                Instant.now()
        );
        if (!resolution.resolved()) {
            log.warn("任务已不存在或已终态，跳过失败裁决: taskId={}, errorType={}",
                    taskId, errorSummary);
            return FailureOutcome.IGNORED;
        }
        if (resolution.deadLetter()) {
            log.error("任务重试耗尽进入死信终态: taskId={}, retryCount={}, errorType={}",
                    taskId, resolution.retryCount(), errorSummary);
            return FailureOutcome.DEAD_LETTERED;
        }
        taskDispatchService.enqueueAt(
                taskId,
                QueueNames.TASK_EXCHANGE,
                routingKey,
                event,
                resolution.nextRetryAt()
        );
        log.warn("任务等待重试: taskId={}, retryCount={}, nextRetryAt={}, errorType={}",
                taskId, resolution.retryCount(), resolution.nextRetryAt(), errorSummary);
        return FailureOutcome.RETRY_SCHEDULED;
    }

    private String errorSummary(Throwable exception) {
        String message = exception.getMessage();
        String summary = message == null || message.isBlank()
                ? exception.getClass().getSimpleName()
                : exception.getClass().getSimpleName() + ": " + message;
        return summary.length() <= MAX_ERROR_LENGTH ? summary : summary.substring(0, MAX_ERROR_LENGTH);
    }

    /**
     * 消费失败裁决结果。
     */
    public enum FailureOutcome {
        IGNORED,
        RETRY_SCHEDULED,
        DEAD_LETTERED
    }
}
