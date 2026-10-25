package com.omninest.worker.photos;

import com.omninest.modules.photos.service.PhotoAiTaskService;
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
 * 照片图像分析任务心跳超时恢复调度器。
 * 扫描运行中心跳超时的任务，交由重试服务做重试或死信裁决。
 *
 * @author OmniNest
 */
@Slf4j
@Component
@RequiredArgsConstructor
@ConditionalOnSchedulerRuntime
public class PhotoAiTaskRecoveryScheduler {

    private static final int RECOVERY_BATCH_SIZE = 100;
    private static final String[] RECOVERED_TASK_TYPES = {
            PhotoAiTaskService.TASK_TYPE_SINGLE,
            PhotoAiTaskService.TASK_TYPE_REANALYSIS
    };

    private final TaskRecordService taskRecordService;
    private final PhotoAiTaskRetryService retryService;

    @Value("${photo.ai.stale-heartbeat-seconds:300}")
    private long staleHeartbeatSeconds;

    /**
     * 扫描并恢复心跳超时的照片图像分析任务。
     */
    @Scheduled(fixedDelayString = "${photo.ai.recovery-interval-millis:60000}")
    public void recoverStaleTasks() {
        Instant cutoff = Instant.now().minus(
                Math.max(60L, staleHeartbeatSeconds),
                ChronoUnit.SECONDS
        );
        for (String taskType : RECOVERED_TASK_TYPES) {
            taskRecordService.listStaleRunningTaskIds(taskType, cutoff, RECOVERY_BATCH_SIZE)
                    .forEach(taskId -> recoverOne(taskId, taskType, cutoff));
        }
    }

    private void recoverOne(UUID taskId, String taskType, Instant cutoff) {
        try {
            retryService.recoverStaleTask(taskId, taskType, cutoff);
        } catch (RuntimeException exception) {
            log.error("照片图像分析任务超时恢复失败: taskId={}", taskId, exception);
        }
    }
}
