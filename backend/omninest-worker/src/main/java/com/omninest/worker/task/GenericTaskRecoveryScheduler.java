package com.omninest.worker.task;

import com.alibaba.fastjson2.JSON;
import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.task.domain.TaskDispatch;
import com.omninest.modules.task.domain.TaskRecord;
import com.omninest.modules.task.repository.TaskDispatchRepository;
import com.omninest.modules.task.service.StaleTaskRecovery;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import com.omninest.modules.task.service.TaskRedispatchService;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnExpression;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * 通用任务恢复调度器。
 *
 * <p>包含两类裁决：一是心跳超时恢复，覆盖缺少专用恢复调度器的长任务类型
 * （PHOTO_SCAN、PHOTO_THUMBNAILS、EXTERNAL_IMPORT、OFFLINE_DOWNLOAD、
 * MEDIA_SCRAPE、VIDEO_TRANSCODE、FILE_INDEX、THUMBNAIL、TEXT_EXTRACTION），
 * Worker 崩溃导致 RUNNING 任务心跳超时后，按重试次数裁决：可重试则经
 * Outbox 按退避时间重新入队，达到上限则进入死信；二是停滞任务清扫，对
 * 长时间停留在 QUEUED/RETRY_WAIT 且无存活投递记录的任务重新投递，兜住
 * "记录已建而消息丢失"的断链场景。</p>
 *
 * <p>已有专用恢复调度器的任务类型（PHOTO_AI、PHOTO_GEO_*、MUSIC_*、COMIC_PARSE、
 * READER_PARSE、FILE_PURGE、MEDIA_AUTO_IMPORT）不参与心跳恢复，避免双重恢复；
 * 停滞清扫作用于全部任务类型，与心跳恢复按状态天然隔离。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Component
@RequiredArgsConstructor
@ConditionalOnExpression("'${omninest.runtime.role:api}' == 'scheduler' || "
        + "('${omninest.runtime.role:api}' == 'api' && ${omninest.runtime.embedded-worker-enabled:false})")
public class GenericTaskRecoveryScheduler {

    /** 需要通用心跳恢复的任务类型。 */
    private static final List<String> RECOVERED_TASK_TYPES = List.of(
            "PHOTO_SCAN",
            "PHOTO_THUMBNAILS",
            "EXTERNAL_IMPORT",
            "OFFLINE_DOWNLOAD",
            "MEDIA_SCRAPE",
            "VIDEO_TRANSCODE",
            "FILE_INDEX",
            "THUMBNAIL",
            "TEXT_EXTRACTION"
    );

    private static final int RECOVERY_BATCH_SIZE = 100;

    /** 投递记录的未决状态，存在任一状态即视为投递链路仍存活。 */
    private static final String DISPATCH_STATUS_PENDING = "PENDING";
    private static final String DISPATCH_STATUS_PUBLISHING = "PUBLISHING";

    private final TaskRecordService taskRecordService;
    private final TaskDispatchRepository taskDispatchRepository;
    private final TaskDispatchService taskDispatchService;
    private final TaskRedispatchService taskRedispatchService;

    @Value("${omninest.task.stale-heartbeat-seconds:600}")
    private long staleHeartbeatSeconds;

    @Value("${omninest.task.stuck-dispatch-seconds:1800}")
    private long stuckDispatchSeconds;

    /**
     * 扫描并恢复心跳超时的通用任务类型。
     */
    @Scheduled(fixedDelayString = "${omninest.task.recovery-interval-millis:60000}")
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

    /**
     * 清扫投递断链的停滞任务并重新投递。
     */
    @Scheduled(fixedDelayString = "${omninest.task.recovery-interval-millis:60000}")
    public void sweepStuckTasks() {
        Instant cutoff = Instant.now().minus(
                Math.max(60L, stuckDispatchSeconds),
                ChronoUnit.SECONDS
        );
        for (TaskRecord record : taskRecordService.listStuckTasks(cutoff, cutoff, RECOVERY_BATCH_SIZE)) {
            redispatchStuckTask(record, cutoff);
        }
    }

    private void recoverOne(UUID taskId, String taskType, Instant cutoff) {
        try {
            StaleTaskRecovery recovery = taskRecordService.recoverStaleTask(
                    taskId,
                    taskType,
                    cutoff,
                    Instant.now(),
                    "WORKER_HEARTBEAT_TIMEOUT"
            );
            if (!recovery.recovered() || recovery.deadLetter()) {
                return;
            }
            republishOriginalMessage(taskId, taskType, recovery.nextRetryAt());
        } catch (RuntimeException exception) {
            log.error("通用任务心跳超时恢复失败: taskType={}, taskId={}", taskType, taskId, exception);
        }
    }

    /**
     * 将任务 Outbox 最近一次投递的原始消息按 nextRetryAt 经 Outbox 延迟重投。
     *
     * <p>重试状态与退避由 {@code recoverStaleTask} 单点完成，这里只负责投递；
     * 重投失败时转入死信，避免任务永久停留在 RETRY_WAIT。</p>
     */
    private void republishOriginalMessage(UUID taskId, String taskType, Instant nextRetryAt) {
        TaskDispatch dispatch = taskDispatchRepository.findFirstByTaskIdOrderByCreatedAtDesc(taskId)
                .orElse(null);
        if (dispatch == null) {
            taskRecordService.markDeadLetter(taskId, "WORKER_HEARTBEAT_TIMEOUT:OUTBOX_MISSING");
            log.warn("通用任务无 Outbox 记录可重投，转入死信: taskType={}, taskId={}", taskType, taskId);
            return;
        }
        try {
            taskDispatchService.enqueueAt(
                    taskId,
                    QueueNames.TASK_EXCHANGE,
                    dispatch.getRoutingKey(),
                    JSON.parse(dispatch.getPayload()),
                    nextRetryAt
            );
            log.warn("通用任务心跳超时已恢复重投: taskType={}, taskId={}, routingKey={}, nextRetryAt={}",
                    taskType, taskId, dispatch.getRoutingKey(), nextRetryAt);
        } catch (RuntimeException exception) {
            taskRecordService.markDeadLetter(taskId, "WORKER_HEARTBEAT_TIMEOUT:REDISPATCH_FAILED");
            log.error("通用任务恢复重投失败，转入死信: taskType={}, taskId={}", taskType, taskId, exception);
        }
    }

    /**
     * 裁决单个停滞任务：无存活投递记录且最近一次投递已超出清扫窗口才重投，
     * 防止与 Outbox 正常投递、延迟重试产生重复消息风暴。
     */
    private void redispatchStuckTask(TaskRecord record, Instant dispatchCutoff) {
        TaskDispatch latest = taskDispatchRepository
                .findFirstByTaskIdOrderByCreatedAtDesc(record.getId())
                .orElse(null);
        if (latest != null
                && (DISPATCH_STATUS_PENDING.equals(latest.getStatus())
                || DISPATCH_STATUS_PUBLISHING.equals(latest.getStatus())
                || latest.getCreatedAt().isAfter(dispatchCutoff))) {
            return;
        }
        try {
            taskRedispatchService.redispatch(record);
            log.warn("停滞任务已重新投递: taskId={}, taskType={}, status={}",
                    record.getId(), record.getTaskType(), record.getStatus());
        } catch (RuntimeException exception) {
            log.error("停滞任务重新投递失败: taskId={}, taskType={}",
                    record.getId(), record.getTaskType(), exception);
        }
    }
}
