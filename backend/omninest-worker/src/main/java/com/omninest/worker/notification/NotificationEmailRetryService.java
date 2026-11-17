package com.omninest.worker.notification;

import com.omninest.common.error.StackSummaries;
import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.notification.event.NotificationEmailRequestedEvent;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import java.time.Duration;
import java.time.Instant;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 通知邮件投递的失败处理：1 分钟、5 分钟、15 分钟各重试一次，第四次进死信。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class NotificationEmailRetryService {

    private static final int MAX_RETRIES = 3;

    private final TaskRecordService taskRecordService;
    private final TaskDispatchService taskDispatchService;

    /**
     * 持久化失败状态并创建延迟 outbox。
     *
     * @param event 邮件投递任务消息
     * @param exception 执行异常
     */
    @Transactional(rollbackFor = Exception.class)
    public void handleFailure(NotificationEmailRequestedEvent event, Throwable exception) {
        int currentRetries = taskRecordService.retryCount(event.taskId());
        String errorSummary = exception.getClass().getSimpleName();
        if (currentRetries >= MAX_RETRIES) {
            taskRecordService.markDeadLetter(
                    event.taskId(),
                    errorSummary,
                    StackSummaries.summarize(exception)
            );
            log.error("邮件投递任务进入死信终态: taskId={}, retryCount={}, errorType={}",
                    event.taskId(), currentRetries, errorSummary);
            return;
        }

        Instant nextRetryAt = Instant.now().plus(retryDelay(currentRetries + 1));
        int retryCount = taskRecordService.markRetryWait(event.taskId(), errorSummary, nextRetryAt);
        taskDispatchService.enqueueAt(
                event.taskId(),
                QueueNames.TASK_EXCHANGE,
                QueueNames.NOTIFICATION_EMAIL_ROUTING_KEY,
                event,
                nextRetryAt
        );
        log.warn("邮件投递任务等待重试: taskId={}, retryCount={}, nextRetryAt={}, errorType={}",
                event.taskId(), retryCount, nextRetryAt, errorSummary);
    }

    private Duration retryDelay(int retryCount) {
        if (retryCount <= 1) {
            return Duration.ofMinutes(1);
        }
        if (retryCount == 2) {
            return Duration.ofMinutes(5);
        }
        return Duration.ofMinutes(15);
    }
}
