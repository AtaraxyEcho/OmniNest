package com.omninest.worker.storage;

import com.omninest.common.storage.ObjectStorageBuckets;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.common.storage.ObjectStorageKey;
import com.omninest.common.storage.ObjectStorageObject;
import com.omninest.common.storage.ObjectStoragePage;
import com.omninest.common.util.RedisUtil;
import com.omninest.modules.file.service.FileIngressObjectReferenceQuery;
import com.omninest.modules.file.service.FileObjectReferenceQuery;
import java.time.Duration;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Set;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import com.omninest.modules.task.runtime.ConditionalOnSchedulerRuntime;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

/**
 * 分页审计原件存储桶，按配置报告或清理没有元数据归属的对象。
 *
 * <p>判据是"存在 {@code file_objects} 行或存在在途入库记录"。文件对象元数据行覆盖了
 * 回收站内的软删除节点、历史版本对象以及永久删除清单尚未执行完的对象；在途入库记录覆盖了
 * 原件已扫描完成但晋升事务还没提交的窗口，因为原件桶里的字节是晋升时由服务端复制出来的。
 * 两者都不成立的对象才是孤儿。</p>
 *
 * <p>与派生资源扫描器的关键差别是原件不可重建：{@code deleteEnabled} 默认关闭，首轮只出报表。
 * 尤其危险的是重设数据库基线（清空 schema 而保留存储桶）之后，桶内全部对象都会被判成孤儿，
 * 此时开启删除开关等于清空用户数据。因此开启删除前必须先人工核对一轮报表。</p>
 *
 * <p>不在本扫描器范围内：分片上传的字节全部落在隔离桶（上传会话的目标桶就是隔离桶），原件桶不会出现
 * 未完成分片。隔离桶侧的滞留由过期上传会话回收任务取消分片、{@code FileQuarantineReaperScheduler}
 * 按入库记录保留期删除隔离对象；两者的存储侧兜底需要对象存储端口暴露"列举未完成分片上传"的能力，
 * 当前端口未暴露，属已记录缺口。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
@ConditionalOnSchedulerRuntime
public class UserFileOrphanScanner {
    private static final String LOCK_KEY = "omninest:maintenance:user-file-orphan-scan:lock";
    private static final String CURSOR_KEY = "omninest:maintenance:user-file-orphan-scan:cursor";

    private final ObjectStorageBuckets objectStorageBuckets;
    private final ObjectStorageClient objectStorageClient;
    private final FileObjectReferenceQuery fileObjectReferenceQuery;
    private final FileIngressObjectReferenceQuery fileIngressObjectReferenceQuery;
    private final RedisUtil redisUtil;
    private final UserFileOrphanScanProperties properties;

    /**
     * 按计划执行一轮原件对象孤儿扫描。
     */
    @Scheduled(cron = "${omninest.storage.user-file-orphan-scan.cleanup-cron:0 5 5 * * *}")
    public void scheduledScan() {
        if (!properties.isEnabled()) {
            return;
        }
        try {
            UserFileOrphanScanResult result = scanOnce();
            if (!result.executed()) {
                log.debug("原件对象孤儿扫描未获得执行锁");
                return;
            }
            log.info(
                    "原件对象孤儿扫描完成: scanned={}, eligible={}, referenced={}, ingressHeld={}, "
                            + "orphan={}, orphanBytes={}, deleted={}, deletedBytes={}, failed={}, "
                            + "pages={}, completed={}, deleteEnabled={}",
                    result.scannedObjects(),
                    result.eligibleObjects(),
                    result.referencedObjects(),
                    result.ingressHeldObjects(),
                    result.orphanObjects(),
                    result.orphanBytes(),
                    result.deletedObjects(),
                    result.deletedBytes(),
                    result.failedDeletions(),
                    result.scannedPages(),
                    result.completed(),
                    properties.isDeleteEnabled()
            );
        } catch (RuntimeException exception) {
            log.error("原件对象孤儿扫描失败: errorType={}", exception.getClass().getSimpleName(), exception);
        }
    }

    /**
     * 执行一轮有界原件对象孤儿扫描。
     *
     * @return 扫描结果
     */
    public UserFileOrphanScanResult scanOnce() {
        validateProperties();
        String lockToken = redisUtil.newLockToken();
        if (!redisUtil.tryLock(LOCK_KEY, lockToken, properties.getLockTtl())) {
            return UserFileOrphanScanResult.skipped();
        }
        try {
            return scanLocked();
        } finally {
            if (!redisUtil.unlock(LOCK_KEY, lockToken)) {
                log.warn("原件对象孤儿扫描锁释放失败");
            }
        }
    }

    private UserFileOrphanScanResult scanLocked() {
        String bucket = objectStorageBuckets.userFiles();
        if (bucket == null || bucket.isBlank()) {
            throw new IllegalStateException("原件存储桶名称不能为空");
        }
        String continuationToken = normalizeToken(redisUtil.get(CURSOR_KEY));
        Instant cutoff = Instant.now().minus(properties.getMinimumAge());
        long scannedObjects = 0;
        long eligibleObjects = 0;
        long referencedObjects = 0;
        long ingressHeldObjects = 0;
        long orphanObjects = 0;
        long orphanBytes = 0;
        long deletedObjects = 0;
        long deletedBytes = 0;
        long failedDeletions = 0;
        int deletionAttempts = 0;
        int scannedPages = 0;
        boolean completed = false;

        while (scannedPages < properties.getMaximumPagesPerRun()) {
            ObjectStoragePage page = objectStorageClient.listObjects(
                    bucket,
                    properties.getPrefix(),
                    continuationToken,
                    properties.getPageSize()
            );
            scannedPages++;
            scannedObjects += page.objects().size();
            Map<String, Long> candidates = new LinkedHashMap<>();
            for (ObjectStorageObject object : page.objects()) {
                if (object.lastModified().isBefore(cutoff)) {
                    candidates.put(object.objectKey(), object.sizeBytes());
                }
            }
            eligibleObjects += candidates.size();

            Set<String> referencedKeys = candidates.isEmpty()
                    ? Set.of()
                    : fileObjectReferenceQuery.findReferencedObjectKeys(bucket, candidates.keySet());
            referencedObjects += referencedKeys.size();
            candidates.keySet().removeAll(referencedKeys);

            Set<String> inFlightKeys = candidates.isEmpty()
                    ? Set.of()
                    : fileIngressObjectReferenceQuery.findInFlightObjectKeys(bucket, candidates.keySet());
            ingressHeldObjects += inFlightKeys.size();
            candidates.keySet().removeAll(inFlightKeys);

            orphanObjects += candidates.size();
            for (Map.Entry<String, Long> candidate : candidates.entrySet()) {
                orphanBytes += candidate.getValue();
                log.debug("原件孤儿对象候选: bucket={}, objectKey={}, sizeBytes={}",
                        bucket, candidate.getKey(), candidate.getValue());
            }

            if (properties.isDeleteEnabled()) {
                for (Map.Entry<String, Long> candidate : candidates.entrySet()) {
                    if (deletionAttempts >= properties.getMaximumDeletesPerRun()) {
                        break;
                    }
                    deletionAttempts++;
                    try {
                        objectStorageClient.removeObject(new ObjectStorageKey(bucket, candidate.getKey()));
                        deletedObjects++;
                        deletedBytes += candidate.getValue();
                    } catch (RuntimeException exception) {
                        failedDeletions++;
                        log.warn("原件孤儿对象删除失败: errorType={}",
                                exception.getClass().getSimpleName());
                    }
                }
            }

            continuationToken = normalizeToken(page.nextContinuationToken());
            completed = continuationToken == null;
            saveCursor(continuationToken);
            if (completed) {
                break;
            }
        }

        return new UserFileOrphanScanResult(
                true,
                scannedObjects,
                eligibleObjects,
                referencedObjects,
                ingressHeldObjects,
                orphanObjects,
                orphanBytes,
                deletedObjects,
                deletedBytes,
                failedDeletions,
                scannedPages,
                completed
        );
    }

    private void saveCursor(String continuationToken) {
        if (continuationToken == null) {
            redisUtil.delete(CURSOR_KEY);
            return;
        }
        redisUtil.set(CURSOR_KEY, continuationToken, properties.getCursorTtl());
    }

    private String normalizeToken(String continuationToken) {
        return continuationToken == null || continuationToken.isBlank()
                ? null
                : continuationToken;
    }

    private void validateProperties() {
        validatePositive(properties.getMinimumAge(), "minimumAge");
        validatePositive(properties.getCursorTtl(), "cursorTtl");
        validatePositive(properties.getLockTtl(), "lockTtl");
        if (properties.getPageSize() < 1 || properties.getPageSize() > 1000) {
            throw new IllegalStateException("原件对象扫描 pageSize 必须在 1 至 1000 之间");
        }
        if (properties.getMaximumPagesPerRun() < 1) {
            throw new IllegalStateException("原件对象扫描 maximumPagesPerRun 必须大于 0");
        }
        if (properties.getMaximumDeletesPerRun() < 1) {
            throw new IllegalStateException("原件对象扫描 maximumDeletesPerRun 必须大于 0");
        }
    }

    private void validatePositive(Duration value, String fieldName) {
        if (value == null || value.isZero() || value.isNegative()) {
            throw new IllegalStateException("原件对象扫描配置必须为正数: " + fieldName);
        }
    }
}
