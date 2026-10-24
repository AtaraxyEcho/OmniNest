package com.omninest.modules.photos.service;

import com.omninest.common.concurrency.DistributedLock;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.json.JsonSupport;
import com.omninest.modules.photos.repository.GeocodeBackfillRow;
import com.omninest.modules.photos.repository.PhotoItemRepository;
import com.omninest.modules.task.service.TaskRecordService;
import java.time.Duration;
import java.time.Instant;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * 存量照片位置回填执行服务（Worker 侧）。
 *
 * <p>以 (created_at, id) keyset 游标分批扫描"有坐标、无地名"的照片；游标与计数器
 * 保存在 sys_tasks.result，与照片更新同事务提交，失败重试后从游标续跑。
 * 写入使用条件更新（仅当照片仍无 city），绝不覆盖用户已有地点。
 * 全局并发由任务去重 + DistributedLock 双重保证，任意时刻至多一个回填在执行。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class PhotoGeoBackfillService {

    /** 执行阶段名。 */
    public static final String PHASE_BACKFILLING = "BACKFILLING";

    private static final String LOCK_KEY = "omninest:photo-geo:backfill";
    private static final Duration LOCK_TTL = Duration.ofHours(2);
    private static final int DEFAULT_BATCH_SIZE = 200;
    private static final int MAX_BATCH_SIZE = 1000;
    private static final String KEY_CURSOR = "cursor";
    private static final String KEY_CURSOR_CREATED_AT = "createdAt";
    private static final String KEY_CURSOR_ID = "id";
    private static final String KEY_UPDATED = "updated";
    private static final String KEY_SKIPPED_EXISTING = "skippedExisting";
    private static final String KEY_SKIPPED_DISTANCE = "skippedDistance";
    private static final String KEY_FAILED = "failed";
    private static final String KEY_PROCESSED = "processed";
    private static final String KEY_TOTAL = "total";

    private final PhotoItemRepository photoItemRepository;
    private final PhotoGeoService photoGeoService;
    private final TaskRecordService taskRecordService;
    private final GeoCityIndex geoCityIndex;
    private final DistributedLock distributedLock;
    private final TransactionTemplate transactionTemplate;

    /**
     * 执行回填任务（由 Worker 消费者调用）。
     *
     * @param taskId 任务 ID
     */
    public void executeBackfillTask(UUID taskId) {
        String token = distributedLock.newToken();
        // 业务级互斥兜底：任务去重无法覆盖多实例同时消费的场景。
        if (!distributedLock.tryLock(LOCK_KEY, token, LOCK_TTL)) {
            throw new BusinessException(ErrorCode.CONFLICT, "已有照片位置回填任务在执行");
        }
        try {
            run(taskId);
        } finally {
            distributedLock.unlock(LOCK_KEY, token);
        }
    }

    private void run(UUID taskId) {
        Map<String, Object> payload = taskRecordService.taskPayload(taskId);
        int batchSize = payloadBatchSize(payload);
        if (!taskRecordService.claimForExecution(taskId, PHASE_BACKFILLING)) {
            return;
        }
        // 整个任务绑定同一数据集版本，避免中途数据集发布导致前后批不一致。
        GeoCitySnapshot pinned = geoCityIndex.snapshotOfVersion(string(payload.get("datasetVersion")));

        Map<String, Object> state = new HashMap<>(taskRecordService.taskResult(taskId));
        long updated = longValue(state.get(KEY_UPDATED));
        long skippedExisting = longValue(state.get(KEY_SKIPPED_EXISTING));
        long skippedDistance = longValue(state.get(KEY_SKIPPED_DISTANCE));
        long failed = longValue(state.get(KEY_FAILED));
        long processed = longValue(state.get(KEY_PROCESSED));
        long total = longValue(state.get(KEY_TOTAL));
        if (total <= 0) {
            total = Math.max(photoItemRepository.countGeocodeBackfillRows(), 1);
        }
        state.put(KEY_TOTAL, total);
        Instant cursorCreatedAt = instant(state);
        UUID cursorId = uuid(state.get(KEY_CURSOR_ID));

        while (true) {
            if (taskRecordService.isCancelled(taskId)) {
                taskRecordService.markCancelled(taskId);
                log.info("照片位置回填任务已取消: taskId={}", taskId);
                return;
            }
            final Instant batchCursorCreatedAt = cursorCreatedAt;
            final UUID batchCursorId = cursorId;
            BackfillBatchOutcome outcome = transactionTemplate.execute(status ->
                    processBatch(taskId, pinned, batchSize, batchCursorCreatedAt, batchCursorId, state));
            if (outcome == null || outcome.rowCount() == 0) {
                break;
            }
            processed += outcome.rowCount();
            updated += outcome.updated();
            skippedExisting += outcome.skippedExisting();
            skippedDistance += outcome.skippedDistance();
            failed += outcome.failed();
            cursorCreatedAt = outcome.lastCreatedAt();
            cursorId = outcome.lastId();

            taskRecordService.updateExecution(
                    taskId,
                    PHASE_BACKFILLING,
                    (int) Math.min(99, processed * 100 / Math.max(total, processed)));
            if (outcome.rowCount() < batchSize) {
                break;
            }
        }

        taskRecordService.markCompleted(taskId, Map.of(
                KEY_UPDATED, updated,
                KEY_SKIPPED_EXISTING, skippedExisting,
                KEY_SKIPPED_DISTANCE, skippedDistance,
                KEY_FAILED, failed));
        log.info("照片位置回填完成: taskId={}, updated={}, skippedExisting={}, skippedDistance={}, failed={}",
                taskId, updated, skippedExisting, skippedDistance, failed);
    }

    /**
     * 处理单批：读取、逆地理编码、条件更新与游标推进在同一事务内，
     * 保证"照片更新成功 = 游标前进"。
     */
    private BackfillBatchOutcome processBatch(
            UUID taskId,
            GeoCitySnapshot pinned,
            int batchSize,
            Instant cursorCreatedAt,
            UUID cursorId,
            Map<String, Object> state) {
        List<GeocodeBackfillRow> rows =
                photoItemRepository.findGeocodeBackfillBatch(cursorCreatedAt, cursorId, batchSize);
        if (rows.isEmpty()) {
            return new BackfillBatchOutcome(0, 0, 0, 0, 0, cursorCreatedAt, cursorId);
        }
        long updated = 0;
        long skippedExisting = 0;
        long skippedDistance = 0;
        long failed = 0;
        Instant lastCreatedAt = cursorCreatedAt;
        UUID lastId = cursorId;
        for (GeocodeBackfillRow row : rows) {
            lastCreatedAt = row.getCreatedAt();
            lastId = row.getId();
            try {
                Map<String, Object> geoInfo =
                        photoGeoService.reverseGeocode(pinned, row.getGpsLatitude(), row.getGpsLongitude());
                if (geoInfo.isEmpty()) {
                    // 含无索引、超距离与非法坐标：均不填充地名，仅推进游标。
                    skippedDistance++;
                    continue;
                }
                int affected = photoItemRepository.updateGeocodeLocationIfAbsent(
                        row.getId(),
                        JsonSupport.toJson(geoInfo),
                        Instant.now());
                if (affected > 0) {
                    updated++;
                } else {
                    // 查询与写入之间照片已被其他写入填充或删除，保持不覆盖原则。
                    skippedExisting++;
                }
            } catch (RuntimeException rowEx) {
                // 单张失败不阻塞整批，仅计数。
                failed++;
                log.warn("单张照片位置回填失败: photoId={}, error={}", row.getId(), rowEx.getMessage());
            }
        }
        state.put(KEY_UPDATED, longValue(state.get(KEY_UPDATED)) + updated);
        state.put(KEY_SKIPPED_EXISTING, longValue(state.get(KEY_SKIPPED_EXISTING)) + skippedExisting);
        state.put(KEY_SKIPPED_DISTANCE, longValue(state.get(KEY_SKIPPED_DISTANCE)) + skippedDistance);
        state.put(KEY_FAILED, longValue(state.get(KEY_FAILED)) + failed);
        state.put(KEY_PROCESSED, longValue(state.get(KEY_PROCESSED)) + rows.size());
        Map<String, Object> resultState = new LinkedHashMap<>(state);
        resultState.put(KEY_CURSOR, Map.of(
                KEY_CURSOR_CREATED_AT, lastCreatedAt == null ? "" : lastCreatedAt.toString(),
                KEY_CURSOR_ID, lastId == null ? "" : lastId.toString()));
        // 游标与照片更新同事务持久化；事务回滚时游标一并回滚。
        taskRecordService.updateResult(taskId, resultState);
        return new BackfillBatchOutcome(rows.size(), updated, skippedExisting, skippedDistance, failed,
                lastCreatedAt, lastId);
    }

    private int payloadBatchSize(Map<String, Object> payload) {
        Object value = payload.get("batchSize");
        if (value == null) {
            return DEFAULT_BATCH_SIZE;
        }
        try {
            return Math.clamp(Integer.parseInt(String.valueOf(value)), 1, MAX_BATCH_SIZE);
        } catch (NumberFormatException ex) {
            return DEFAULT_BATCH_SIZE;
        }
    }

    private static Instant instant(Map<String, Object> state) {
        Object cursor = state.get(KEY_CURSOR);
        if (!(cursor instanceof Map<?, ?> cursorMap)) {
            return null;
        }
        Object createdAt = cursorMap.get(KEY_CURSOR_CREATED_AT);
        if (createdAt == null || String.valueOf(createdAt).isBlank()) {
            return null;
        }
        try {
            return Instant.parse(String.valueOf(createdAt));
        } catch (RuntimeException ex) {
            return null;
        }
    }

    private static UUID uuid(Object value) {
        try {
            return value == null || String.valueOf(value).isBlank()
                    ? null
                    : UUID.fromString(String.valueOf(value));
        } catch (IllegalArgumentException ex) {
            return null;
        }
    }

    private static long longValue(Object value) {
        if (value instanceof Number number) {
            return number.longValue();
        }
        try {
            return value == null ? 0 : Long.parseLong(String.valueOf(value));
        } catch (NumberFormatException ex) {
            return 0;
        }
    }

    private static String string(Object value) {
        return value == null ? null : String.valueOf(value);
    }

    /** 单批处理结果。 */
    private record BackfillBatchOutcome(
            int rowCount,
            long updated,
            long skippedExisting,
            long skippedDistance,
            long failed,
            Instant lastCreatedAt,
            UUID lastId) {
    }
}
