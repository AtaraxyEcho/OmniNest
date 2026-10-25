package com.omninest.worker.file;

import com.omninest.modules.file.service.FilePurgeRetryService;
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
 * 恢复因 Worker 退出而失去心跳的文件永久删除任务。
 *
 * @author OmniNest
 */
@Slf4j
@Component
@RequiredArgsConstructor
@ConditionalOnSchedulerRuntime
public class FilePurgeRecoveryScheduler {
    private static final String TASK_TYPE = "FILE_PURGE";
    private static final int RECOVERY_BATCH_SIZE = 100;

    private final TaskRecordService taskRecordService;
    private final FilePurgeRetryService retryService;

    @Value("${omninest.file-purge.stale-heartbeat-seconds:120}")
    private long staleHeartbeatSeconds;

    /**
     * 扫描并恢复心跳超时任务。
     */
    @Scheduled(fixedDelayString = "${omninest.file-purge.recovery-interval-millis:30000}")
    public void recoverStaleTasks() {
        Instant cutoff = Instant.now().minus(
                Math.max(30L, staleHeartbeatSeconds),
                ChronoUnit.SECONDS
        );
        taskRecordService.listStaleRunningTaskIds(TASK_TYPE, cutoff, RECOVERY_BATCH_SIZE)
                .forEach(taskId -> recoverOne(taskId, cutoff));
    }

    private void recoverOne(UUID taskId, Instant cutoff) {
        try {
            retryService.recoverStaleTask(taskId, cutoff);
        } catch (RuntimeException exception) {
            log.error("文件永久删除超时任务恢复失败: taskId={}, errorType={}",
                    taskId, exception.getClass().getSimpleName(), exception);
        }
    }
}
