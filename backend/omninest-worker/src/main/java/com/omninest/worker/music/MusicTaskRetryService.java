package com.omninest.worker.music;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.error.StackSummaries;
import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.music.event.MusicScanEvent;
import com.omninest.modules.music.event.MusicScrapeEvent;
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
 * 音乐扫描和刮削任务的失败重试与心跳恢复服务。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class MusicTaskRetryService {
    private static final int MAX_RETRIES = 3;
    private static final String SCAN_TASK_TYPE = "MUSIC_SCAN";
    private static final String SCRAPE_TASK_TYPE = "MUSIC_SCRAPE";

    private final TaskRecordService taskRecordService;
    private final TaskDispatchService taskDispatchService;

    /**
     * 处理音乐扫描失败。
     *
     * @param event 原扫描事件
     * @param exception 执行异常
     */
    @Transactional(rollbackFor = Exception.class)
    public void handleScanFailure(MusicScanEvent event, Throwable exception) {
        handleFailure(
                event.jobId(),
                QueueNames.MUSIC_SCAN_ROUTING_KEY,
                event,
                exception
        );
    }

    /**
     * 处理音乐刮削失败。
     *
     * @param event 原刮削事件
     * @param exception 执行异常
     */
    @Transactional(rollbackFor = Exception.class)
    public void handleScrapeFailure(MusicScrapeEvent event, Throwable exception) {
        handleFailure(
                event.jobId(),
                QueueNames.MUSIC_SCRAPE_ROUTING_KEY,
                event,
                exception
        );
    }

    /**
     * 恢复心跳超时的音乐扫描任务。
     *
     * @param taskId 任务 ID
     * @param heartbeatCutoff 心跳截止时间
     */
    @Transactional(rollbackFor = Exception.class)
    public void recoverStaleScanTask(UUID taskId, Instant heartbeatCutoff) {
        Map<String, Object> payload = taskRecordService.taskPayload(taskId);
        MusicScanEvent event = scanEvent(payload);
        StaleTaskRecovery recovery = taskRecordService.recoverStaleTask(
                taskId,
                SCAN_TASK_TYPE,
                heartbeatCutoff,
                Instant.now(),
                "WORKER_HEARTBEAT_TIMEOUT"
        );
        if (recovery.recovered() && !recovery.deadLetter()) {
            enqueueRetry(taskId, QueueNames.MUSIC_SCAN_ROUTING_KEY, event, recovery.nextRetryAt());
        }
    }

    /**
     * 恢复心跳超时的音乐刮削任务。
     *
     * @param taskId 任务 ID
     * @param heartbeatCutoff 心跳截止时间
     */
    @Transactional(rollbackFor = Exception.class)
    public void recoverStaleScrapeTask(UUID taskId, Instant heartbeatCutoff) {
        Map<String, Object> payload = taskRecordService.taskPayload(taskId);
        MusicScrapeEvent event = scrapeEvent(payload);
        StaleTaskRecovery recovery = taskRecordService.recoverStaleTask(
                taskId,
                SCRAPE_TASK_TYPE,
                heartbeatCutoff,
                Instant.now(),
                "WORKER_HEARTBEAT_TIMEOUT"
        );
        if (recovery.recovered() && !recovery.deadLetter()) {
            enqueueRetry(taskId, QueueNames.MUSIC_SCRAPE_ROUTING_KEY, event, recovery.nextRetryAt());
        }
    }

    private void handleFailure(
            UUID taskId,
            String routingKey,
            Object event,
            Throwable exception
    ) {
        String errorSummary = errorSummary(exception);
        String stackSummary = StackSummaries.summarize(exception);
        if (isNonRetryable(exception)) {
            taskRecordService.markDeadLetter(taskId, errorSummary, stackSummary);
            log.warn("音乐任务因业务错误进入死信终态: taskId={}, errorType={}", taskId, errorSummary);
            return;
        }

        int currentRetries = taskRecordService.retryCount(taskId);
        if (currentRetries >= MAX_RETRIES) {
            taskRecordService.markDeadLetter(taskId, errorSummary, stackSummary);
            log.error("音乐任务达到最大重试次数并进入死信: taskId={}, retryCount={}, errorType={}",
                    taskId, currentRetries, errorSummary);
            return;
        }

        Instant nextRetryAt = Instant.now().plus(retryDelay(currentRetries + 1));
        int retryCount = taskRecordService.markRetryWait(taskId, errorSummary, nextRetryAt);
        enqueueRetry(taskId, routingKey, event, nextRetryAt);
        log.warn("音乐任务等待重试: taskId={}, retryCount={}, nextRetryAt={}, errorType={}",
                taskId, retryCount, nextRetryAt, errorSummary);
    }

    private void enqueueRetry(UUID taskId, String routingKey, Object event, Instant nextRetryAt) {
        taskDispatchService.enqueueAt(
                taskId,
                QueueNames.TASK_EXCHANGE,
                routingKey,
                event,
                nextRetryAt
        );
    }

    private MusicScanEvent scanEvent(Map<String, Object> payload) {
        return new MusicScanEvent(
                requiredUuid(payload, "jobId"),
                requiredUuid(payload, "ownerUserId")
        );
    }

    private MusicScrapeEvent scrapeEvent(Map<String, Object> payload) {
        return new MusicScrapeEvent(
                requiredUuid(payload, "jobId"),
                requiredUuid(payload, "ownerUserId"),
                Boolean.parseBoolean(String.valueOf(payload.getOrDefault("force", false)))
        );
    }

    private UUID requiredUuid(Map<String, Object> payload, String key) {
        Object value = payload.get(key);
        try {
            return UUID.fromString(String.valueOf(value));
        } catch (IllegalArgumentException exception) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "音乐任务载荷字段格式错误: " + key);
        }
    }

    private boolean isNonRetryable(Throwable exception) {
        if (!(exception instanceof BusinessException businessException)) {
            return false;
        }
        return switch (businessException.errorCode()) {
            case PARAM_ERROR, BAD_REQUEST, VALIDATION_FAILED, NOT_FOUND, TASK_NOT_FOUND,
                    FORBIDDEN, FILE_NOT_FOUND, MUSIC_PLATFORM_NOT_CONNECTED,
                    MUSIC_PLATFORM_AUTH_EXPIRED -> true;
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
}
