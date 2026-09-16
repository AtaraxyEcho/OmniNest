package com.omninest.worker.media;

import com.omninest.modules.backdrop.service.BackdropScanRetryService;
import com.omninest.modules.task.service.TaskRecordService;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnExpression;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * 恢复因 Worker 退出而失去心跳的背景素材安全扫描任务。
 * 默认心跳阈值需大于单次扫描时长上限（clamd MaxScanTime 30 分钟 + 客户端超时余量）。
 *
 * @author OmniNest
 */
@Slf4j
@Component
@RequiredArgsConstructor
@ConditionalOnExpression("'${omninest.runtime.role:api}' == 'scheduler' || "
        + "('${omninest.runtime.role:api}' == 'api' && ${omninest.runtime.embedded-worker-enabled:false})")
public class BackdropSecurityScanRecoveryScheduler {
    private static final String TASK_TYPE = "BACKDROP_SECURITY_SCAN";
    private static final int RECOVERY_BATCH_SIZE = 100;

    private final TaskRecordService taskRecordService;
    private final BackdropScanRetryService retryService;

    @Value("${omninest.backdrop-security-scan.stale-heartbeat-seconds:2700}")
    private long staleHeartbeatSeconds;

    /**
     * 扫描并恢复心跳超时任务。
     */
    @Scheduled(fixedDelayString = "${omninest.backdrop-security-scan.recovery-interval-millis:60000}")
    public void recoverStaleTasks() {
        Instant cutoff = Instant.now().minus(
                Math.max(30L, staleHeartbeatSeconds),
                ChronoUnit.SECONDS
        );
        taskRecordService.listStaleRunningTaskIds(TASK_TYPE, cutoff, RECOVERY_BATCH_SIZE)
                .forEach(this::recoverOne);
    }

    private void recoverOne(UUID taskId) {
        try {
            retryService.recoverStaleTask(taskId, Instant.now().minusSeconds(staleHeartbeatSeconds));
        } catch (RuntimeException exception) {
            log.error("背景素材安全扫描超时任务恢复失败: taskId={}, errorType={}",
                    taskId, exception.getClass().getSimpleName());
        }
    }
}
