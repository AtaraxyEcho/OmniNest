package com.omninest.worker.task;

import com.omninest.common.concurrency.DistributedLock;
import com.omninest.common.json.JsonSupport;
import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.task.domain.TaskRecord;
import com.omninest.modules.task.service.StaleTaskRecovery;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import com.omninest.modules.task.service.TaskRedispatchService;
import java.time.Duration;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import com.omninest.modules.task.runtime.ConditionalOnSchedulerRuntime;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * 通用任务恢复调度器。
 *
 * <p>包含两类裁决：一是心跳超时恢复，覆盖缺少专用恢复调度器的长任务类型
 * （PHOTO_SCAN、PHOTO_THUMBNAILS、PHOTO_BATCH、PHOTO_MOTION、
 * PHOTO_MOTION_RESCAN、EXTERNAL_IMPORT、MEDIA_SCRAPE、VIDEO_TRANSCODE、
 * WEB_OPTIMIZE、AUDIO_EXTRACT、FILE_INDEX、THUMBNAIL、
 * TEXT_EXTRACTION、SEARCH_INDEX_REBUILD、NOTIFICATION_EMAIL、
 * LOCAL_VIDEO_LIBRARY_DISCOVERY、LOCAL_VIDEO_LIBRARY_APPLY），
 * Worker 崩溃导致 RUNNING 任务心跳超时后，按重试次数裁决：可重试则经
 * Outbox 按退避时间重新入队，达到上限则进入死信；二是停滞任务清扫，对
 * 长时间停留在 QUEUED/RETRY_WAIT 且无存活投递记录的任务重新投递，兜住
 * "记录已建而消息丢失"的断链场景。MEDIA_SCAN 不在心跳恢复之列：其消费者
 * 不领取 RUNNING（执行期间停留在 QUEUED），由停滞清扫统一兜底。</p>
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
@ConditionalOnSchedulerRuntime
public class GenericTaskRecoveryScheduler {

    /** 需要通用心跳恢复的任务类型。 */
    private static final List<String> RECOVERED_TASK_TYPES = List.of(
            "PHOTO_SCAN",
            "PHOTO_THUMBNAILS",
            "PHOTO_BATCH",
            "PHOTO_MOTION",
            "PHOTO_MOTION_RESCAN",
            "EXTERNAL_IMPORT",
            "MEDIA_SCRAPE",
            "VIDEO_TRANSCODE",
            "WEB_OPTIMIZE",
            "AUDIO_EXTRACT",
            "THUMBNAIL",
            "TEXT_EXTRACTION",
            "SEARCH_INDEX_REBUILD",
            "NOTIFICATION_EMAIL",
            "LOCAL_VIDEO_LIBRARY_DISCOVERY",
            "LOCAL_VIDEO_LIBRARY_APPLY"
    );

    private static final int RECOVERY_BATCH_SIZE = 100;

    /** 投递记录的未决状态，存在任一状态即视为投递链路仍存活。 */
    private static final String DISPATCH_STATUS_PENDING = "PENDING";
    private static final String DISPATCH_STATUS_PUBLISHING = "PUBLISHING";

    /**
     * 停滞任务清扫的互斥键与有效期：有效期覆盖一轮批量清扫的最坏耗时。
     */
    private static final String SWEEP_LOCK_KEY = "omninest:task:sweep-stuck";
    private static final Duration SWEEP_LOCK_TTL = Duration.ofMinutes(5);

    /**
     * 心跳超时恢复的互斥键与有效期：多实例并发恢复会对同一任务重复重投，
     * 重投不改 {@code retryCount}，等于绕过 1/5/15 分钟 ×3 的重试上限。
     */
    private static final String RECOVER_LOCK_KEY = "omninest:task:recover-stale";
    private static final Duration RECOVER_LOCK_TTL = Duration.ofMinutes(5);

    private final TaskRecordService taskRecordService;
    private final DistributedLock distributedLock;
    private final TaskDispatchService taskDispatchService;
    private final TaskRedispatchService taskRedispatchService;
    private final TransactionTemplate transactionTemplate;

    @Value("${omninest.task.stale-heartbeat-seconds:600}")
    private long staleHeartbeatSeconds;

    @Value("${omninest.task.stuck-dispatch-seconds:1800}")
    private long stuckDispatchSeconds;

    /**
     * 扫描并恢复心跳超时的通用任务类型。
     */
    @Scheduled(fixedDelayString = "${omninest.task.recovery-interval-millis:60000}")
    public void recoverStaleTasks() {
        String lockToken = distributedLock.newToken();
        if (!distributedLock.tryLock(RECOVER_LOCK_KEY, lockToken, RECOVER_LOCK_TTL)) {
            log.debug("心跳超时恢复已被其他实例持有，本轮跳过");
            return;
        }
        try {
            Instant cutoff = Instant.now().minus(
                    Math.max(60L, staleHeartbeatSeconds),
                    ChronoUnit.SECONDS
            );
            for (String taskType : RECOVERED_TASK_TYPES) {
                taskRecordService.listStaleRunningTaskIds(taskType, cutoff, RECOVERY_BATCH_SIZE)
                        .forEach(taskId -> recoverOne(taskId, taskType, cutoff));
            }
        } finally {
            distributedLock.unlock(RECOVER_LOCK_KEY, lockToken);
        }
    }

    /**
     * 清扫投递断链的停滞任务并重新投递。
     *
     * <p>多实例同时清扫会对同一任务读后重投：重投不改 {@code retryCount}，
     * 并发重投等于绕过 1/5/15 分钟 ×3 的重试上限，因此与孤儿扫描器一样先取互斥锁。</p>
     */
    @Scheduled(fixedDelayString = "${omninest.task.recovery-interval-millis:60000}")
    public void sweepStuckTasks() {
        String lockToken = distributedLock.newToken();
        if (!distributedLock.tryLock(SWEEP_LOCK_KEY, lockToken, SWEEP_LOCK_TTL)) {
            log.debug("停滞任务清扫已被其他实例持有，本轮跳过");
            return;
        }
        try {
            Instant cutoff = Instant.now().minus(
                    Math.max(60L, stuckDispatchSeconds),
                    ChronoUnit.SECONDS
            );
            List<TaskRecord> stuck = taskRecordService.listStuckTasks(cutoff, cutoff, RECOVERY_BATCH_SIZE);
            if (stuck.isEmpty()) {
                return;
            }
            Map<UUID, TaskDispatchService.TaskDispatchRoute> latestRoutes = taskDispatchService.latestRoutes(
                    stuck.stream().map(TaskRecord::getId).toList());
            for (TaskRecord record : stuck) {
                redispatchStuckTask(record, cutoff, latestRoutes.get(record.getId()));
            }
        } finally {
            distributedLock.unlock(SWEEP_LOCK_KEY, lockToken);
        }
    }

    private void recoverOne(UUID taskId, String taskType, Instant cutoff) {
        try {
            // 状态裁决与重投必须在同一事务内：先提交 RETRY_WAIT 再插 Outbox，
            // 中断在两步之间会让任务永久停在重试等待且没有消息可投递。
            transactionTemplate.executeWithoutResult(status -> {
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
            });
        } catch (RuntimeException exception) {
            log.error("通用任务心跳超时恢复失败: taskType={}, taskId={}", taskType, taskId, exception);
        }
    }

    /**
     * 将任务 Outbox 最近一次投递的原始消息按 nextRetryAt 经 Outbox 延迟重投。
     *
     * <p>重试状态与退避由 {@code recoverStaleTask} 单点完成，这里只负责投递。
     * 投递异常会让整笔恢复事务回滚，任务保持 RUNNING 并在下一轮重新裁决，
     * 不得在此处直接判死信——那只会在数据库瞬断时把本可恢复的任务永久终结。</p>
     */
    private void republishOriginalMessage(UUID taskId, String taskType, Instant nextRetryAt) {
        TaskDispatchService.TaskDispatchRoute route = taskDispatchService.latestRoute(taskId).orElse(null);
        if (route == null) {
            taskRecordService.markDeadLetter(taskId, "WORKER_HEARTBEAT_TIMEOUT:OUTBOX_MISSING");
            log.warn("通用任务无 Outbox 记录可重投，转入死信: taskType={}, taskId={}", taskType, taskId);
            return;
        }
        taskDispatchService.enqueueAt(
                taskId,
                QueueNames.TASK_EXCHANGE,
                route.routingKey(),
                JsonSupport.fromJson(route.payloadJson(), Object.class),
                nextRetryAt
        );
        log.warn("通用任务心跳超时已恢复重投: taskType={}, taskId={}, routingKey={}, nextRetryAt={}",
                taskType, taskId, route.routingKey(), nextRetryAt);
    }

    /**
     * 裁决单个停滞任务：无存活投递记录且最近一次投递已超出清扫窗口才重投，
     * 防止与 Outbox 正常投递、延迟重试产生重复消息风暴。
     */
    private void redispatchStuckTask(
            TaskRecord record,
            Instant dispatchCutoff,
            TaskDispatchService.TaskDispatchRoute latest
    ) {
        if (latest != null
                && (DISPATCH_STATUS_PENDING.equals(latest.status())
                || DISPATCH_STATUS_PUBLISHING.equals(latest.status())
                || latest.createdAt().isAfter(dispatchCutoff))) {
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
