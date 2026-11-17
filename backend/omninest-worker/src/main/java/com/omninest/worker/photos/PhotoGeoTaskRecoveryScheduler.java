package com.omninest.worker.photos;

import com.omninest.common.concurrency.DistributedLock;
import com.omninest.modules.photos.service.GeoDatasetService;
import com.omninest.modules.task.service.TaskRecordService;
import java.time.Duration;
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
 * 照片 GeoNames 导入与位置回填任务的心跳超时恢复调度器。
 * 扫描运行中心跳超时的任务，交由重试服务做重试或死信裁决。
 *
 * @author OmniNest
 */
@Slf4j
@Component
@RequiredArgsConstructor
@ConditionalOnSchedulerRuntime
public class PhotoGeoTaskRecoveryScheduler {

    /** 多实例部署下同一批超时任务只能由一个实例重投。 */
    private static final String RECOVERY_LOCK_KEY = "omninest:worker:recovery:photo-geo-task";
    private static final Duration RECOVERY_LOCK_TTL = Duration.ofMinutes(2);

    private static final int RECOVERY_BATCH_SIZE = 100;

    private final TaskRecordService taskRecordService;
    private final DistributedLock distributedLock;
    private final PhotoGeoImportRetryService importRetryService;
    private final PhotoGeoBackfillRetryService backfillRetryService;

    @Value("${photo.geo.stale-heartbeat-seconds:600}")
    private long staleHeartbeatSeconds;

    /**
     * 扫描并恢复心跳超时的 GeoNames 任务。
     */
    @Scheduled(fixedDelayString = "${photo.geo.recovery-interval-millis:60000}")
    public void recoverStaleTasks() {
        String token = distributedLock.newToken();
        if (!distributedLock.tryLock(RECOVERY_LOCK_KEY, token, RECOVERY_LOCK_TTL)) {
            return;
        }
        try {
            Instant cutoff = Instant.now().minus(
                    Math.max(60L, staleHeartbeatSeconds),
                    ChronoUnit.SECONDS
            );
            taskRecordService.listStaleRunningTaskIds(
                            GeoDatasetService.TASK_TYPE_IMPORT, cutoff, RECOVERY_BATCH_SIZE)
                    .forEach(taskId -> recoverOne(taskId, "IMPORT", () ->
                            importRetryService.recoverStaleTask(taskId, cutoff)));
            taskRecordService.listStaleRunningTaskIds(
                            GeoDatasetService.TASK_TYPE_BACKFILL, cutoff, RECOVERY_BATCH_SIZE)
                    .forEach(taskId -> recoverOne(taskId, "BACKFILL", () ->
                            backfillRetryService.recoverStaleTask(taskId, cutoff)));
        } finally {
            distributedLock.unlock(RECOVERY_LOCK_KEY, token);
        }
    }

    private void recoverOne(UUID taskId, String kind, Runnable recoveryAction) {
        try {
            recoveryAction.run();
        } catch (RuntimeException exception) {
            log.error("照片 GeoNames 任务超时恢复失败: kind={}, taskId={}", kind, taskId, exception);
        }
    }
}
