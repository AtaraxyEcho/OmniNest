package com.omninest.worker.reader;

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
 * 文本书籍解析任务心跳超时恢复调度器。
 *
 * @author OmniNest
 */
@Slf4j
@Component
@RequiredArgsConstructor
@ConditionalOnSchedulerRuntime
public class ReaderTextParseRecoveryScheduler {

    private static final String TASK_TYPE = "READER_PARSE";
    private static final int RECOVERY_BATCH_SIZE = 100;

    private final TaskRecordService taskRecordService;
    private final ReaderTextParseRetryService retryService;

    @Value("${omninest.reader.text-parser.stale-heartbeat-seconds:120}")
    private long staleHeartbeatSeconds;

    /**
     * 扫描并恢复心跳超时任务。
     */
    @Scheduled(fixedDelayString = "${omninest.reader.text-parser.recovery-interval-millis:30000}")
    public void recoverStaleTasks() {
        Instant cutoff = Instant.now().minus(Math.max(30L, staleHeartbeatSeconds), ChronoUnit.SECONDS);
        taskRecordService.listStaleRunningTaskIds(TASK_TYPE, cutoff, RECOVERY_BATCH_SIZE)
                .forEach(taskId -> recoverOne(taskId, cutoff));
    }

    private void recoverOne(UUID taskId, Instant cutoff) {
        try {
            retryService.recoverStaleTask(taskId, cutoff);
        } catch (RuntimeException exception) {
            log.error("文本书籍解析超时任务恢复失败: taskId={}", taskId, exception);
        }
    }
}
