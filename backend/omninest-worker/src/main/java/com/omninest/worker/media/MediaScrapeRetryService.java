package com.omninest.worker.media;

import com.omninest.common.error.StackSummaries;
import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import com.omninest.modules.video.event.MediaScrapeRequestedEvent;
import java.time.Duration;
import java.time.Instant;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 媒体刮削任务失败重试服务。
 *
 * <p>与媒体自动导入重试同构：状态置 RETRY_WAIT 并经 Outbox 延迟重投，
 * 携带 1/5/15 分钟退避；持久化失败时异常向上抛出，由消费者 nack 进死信，
 * 不再出现"吞异常后消息丢失"的僵尸任务。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class MediaScrapeRetryService {
    private static final int MAX_RETRIES = 3;

    private final TaskRecordService taskRecordService;
    private final TaskDispatchService taskDispatchService;

    /**
     * 持久化失败状态并创建延迟 Outbox 投递。
     *
     * @param event 媒体刮削任务消息
     * @param exception 执行异常
     */
    @Transactional(rollbackFor = Exception.class)
    public void handleFailure(MediaScrapeRequestedEvent event, Throwable exception) {
        int currentRetries = taskRecordService.retryCount(event.taskId());
        String errorSummary = exception.getClass().getSimpleName();
        if (currentRetries >= MAX_RETRIES) {
            taskRecordService.markDeadLetter(
                    event.taskId(),
                    "重试次数已耗尽: " + errorSummary,
                    StackSummaries.summarize(exception)
            );
            log.error("媒体刮削任务进入死信终态: taskId={}, retryCount={}, errorType={}",
                    event.taskId(), currentRetries, errorSummary);
            return;
        }
        Instant nextRetryAt = Instant.now().plus(retryDelay(currentRetries + 1));
        int retryCount = taskRecordService.markRetryWait(event.taskId(), errorSummary, nextRetryAt);
        taskDispatchService.enqueueAt(
                event.taskId(),
                QueueNames.TASK_EXCHANGE,
                QueueNames.MEDIA_SCRAPE_ROUTING_KEY,
                event,
                nextRetryAt
        );
        log.warn("媒体刮削任务等待重试: taskId={}, retryCount={}, nextRetryAt={}, errorType={}",
                event.taskId(), retryCount, nextRetryAt, errorSummary);
    }

    private Duration retryDelay(int retryCount) {
        return switch (retryCount) {
            case 1 -> Duration.ofMinutes(1);
            case 2 -> Duration.ofMinutes(5);
            default -> Duration.ofMinutes(15);
        };
    }
}
