package com.omninest.worker.music;

import com.omninest.modules.task.service.TaskRecordService;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import com.omninest.modules.task.runtime.ConditionalOnSchedulerRuntime;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * 音乐任务心跳超时恢复调度器。
 *
 * @author OmniNest
 */
@Slf4j
@Component
@RequiredArgsConstructor
@ConditionalOnSchedulerRuntime
public class MusicTaskRecoveryScheduler {
    private static final int RECOVERY_BATCH_SIZE = 100;

    private final TaskRecordService taskRecordService;
    private final MusicTaskRetryService retryService;

    @Value("${music.task.stale-heartbeat-seconds:120}")
    private long staleHeartbeatSeconds;

    /**
     * 扫描并恢复心跳超时的音乐任务。
     */
    @Scheduled(fixedDelayString = "${music.task.recovery-interval-millis:30000}")
    public void recoverStaleTasks() {
        Instant cutoff = Instant.now().minus(
                Math.max(30L, staleHeartbeatSeconds),
                ChronoUnit.SECONDS
        );
        recoverType("MUSIC_SCAN", cutoff, retryService::recoverStaleScanTask);
        recoverType("MUSIC_SCRAPE", cutoff, retryService::recoverStaleScrapeTask);
    }

    private void recoverType(
            String taskType,
            Instant cutoff,
            StaleTaskRecoveryAction recoveryAction
    ) {
        taskRecordService.listStaleRunningTaskIds(taskType, cutoff, RECOVERY_BATCH_SIZE)
                .forEach(taskId -> recoverOne(taskId, cutoff, recoveryAction));
    }

    private void recoverOne(
            UUID taskId,
            Instant cutoff,
            StaleTaskRecoveryAction recoveryAction
    ) {
        try {
            recoveryAction.recover(taskId, cutoff);
        } catch (RuntimeException exception) {
            log.error("音乐任务超时恢复失败: taskId={}", taskId, exception);
        }
    }

    @FunctionalInterface
    private interface StaleTaskRecoveryAction {
        void recover(UUID taskId, Instant cutoff);
    }
}
