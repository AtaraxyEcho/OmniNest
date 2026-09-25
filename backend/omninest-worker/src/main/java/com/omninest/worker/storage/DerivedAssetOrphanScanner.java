package com.omninest.worker.storage;

import com.omninest.common.storage.ObjectStorageBuckets;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.common.storage.ObjectStorageKey;
import com.omninest.common.storage.ObjectStorageObject;
import com.omninest.common.storage.ObjectStoragePage;
import com.omninest.common.util.RedisUtil;
import com.omninest.modules.file.service.DerivedObjectReferenceQuery;
import com.omninest.modules.file.service.FileObjectReferenceQuery;
import com.omninest.modules.reader.service.ReaderPageAssetReferenceQuery;
import com.omninest.modules.user.service.UserAvatarObjectReferenceQuery;
import java.time.Duration;
import java.time.Instant;
import java.util.HashSet;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

/**
 * 分页审计派生资源存储桶，并按配置清理没有元数据引用的对象。
 *
 * <p>引用源通过统一 SPI 报告：FileObject（含 Photo 缩略图/Transcode/Backdrop/
 * Music 封面等 DerivedAssetStorageService 写入）、Reader 页面资产与用户头像。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
@ConditionalOnProperty(prefix = "omninest.runtime", name = "role", havingValue = "scheduler")
public class DerivedAssetOrphanScanner {
    private static final String LOCK_KEY = "omninest:maintenance:derived-orphan-scan:lock";
    private static final String CURSOR_KEY = "omninest:maintenance:derived-orphan-scan:cursor";

    private final ObjectStorageBuckets objectStorageBuckets;
    private final ObjectStorageClient objectStorageClient;
    private final FileObjectReferenceQuery fileObjectReferenceQuery;
    private final ReaderPageAssetReferenceQuery readerPageAssetReferenceQuery;
    private final UserAvatarObjectReferenceQuery userAvatarObjectReferenceQuery;
    /** 额外派生对象引用源；FileObject 已单独注入，这里放其余 SPI 实现。 */
    private final List<DerivedObjectReferenceQuery> derivedObjectReferenceQueries;
    private final RedisUtil redisUtil;
    private final DerivedAssetOrphanScanProperties properties;

    /**
     * 按计划执行一轮派生对象孤儿扫描。
     */
    @Scheduled(cron = "${omninest.storage.derived-orphan-scan.cleanup-cron:0 15 4 * * *}")
    public void scheduledScan() {
        if (!properties.isEnabled()) {
            return;
        }
        try {
            DerivedAssetOrphanScanResult result = scanOnce();
            if (!result.executed()) {
                log.debug("派生对象孤儿扫描未获得执行锁");
                return;
            }
            log.info(
                    "派生对象孤儿扫描完成: scanned={}, eligible={}, referenced={}, orphaned={}, "
                            + "deleted={}, failed={}, pages={}, completed={}, deleteEnabled={}",
                    result.scannedObjects(),
                    result.eligibleObjects(),
                    result.referencedObjects(),
                    result.orphanObjects(),
                    result.deletedObjects(),
                    result.failedDeletions(),
                    result.scannedPages(),
                    result.completed(),
                    properties.isDeleteEnabled()
            );
        } catch (RuntimeException exception) {
            log.error("派生对象孤儿扫描失败: errorType={}", exception.getClass().getSimpleName(), exception);
        }
    }

    /**
     * 执行一轮有界派生对象孤儿扫描。
     *
     * @return 扫描结果
     */
    public DerivedAssetOrphanScanResult scanOnce() {
        validateProperties();
        String lockToken = redisUtil.newLockToken();
        if (!redisUtil.tryLock(LOCK_KEY, lockToken, properties.getLockTtl())) {
            return DerivedAssetOrphanScanResult.skipped();
        }
        try {
            return scanLocked();
        } finally {
            if (!redisUtil.unlock(LOCK_KEY, lockToken)) {
                log.warn("派生对象孤儿扫描锁释放失败");
            }
        }
    }

    private DerivedAssetOrphanScanResult scanLocked() {
        String bucket = objectStorageBuckets.derivedAssets();
        if (bucket == null || bucket.isBlank()) {
            throw new IllegalStateException("派生资源存储桶名称不能为空");
        }
        String continuationToken = normalizeToken(redisUtil.get(CURSOR_KEY));
        Instant cutoff = Instant.now().minus(properties.getMinimumAge());
        long scannedObjects = 0;
        long eligibleObjects = 0;
        long referencedObjects = 0;
        long orphanObjects = 0;
        long deletedObjects = 0;
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
            List<ObjectStorageObject> eligible = page.objects().stream()
                    .filter(object -> object.lastModified().isBefore(cutoff))
                    .toList();
            eligibleObjects += eligible.size();

            Set<String> candidateKeys = new LinkedHashSet<>();
            eligible.forEach(object -> candidateKeys.add(object.objectKey()));
            Set<String> referencedKeys = findReferencedKeys(bucket, candidateKeys);
            referencedObjects += referencedKeys.size();
            candidateKeys.removeAll(referencedKeys);
            orphanObjects += candidateKeys.size();

            if (properties.isDeleteEnabled()) {
                for (String objectKey : candidateKeys) {
                    if (deletionAttempts >= properties.getMaximumDeletesPerRun()) {
                        break;
                    }
                    deletionAttempts++;
                    try {
                        objectStorageClient.removeObject(new ObjectStorageKey(bucket, objectKey));
                        deletedObjects++;
                    } catch (RuntimeException exception) {
                        failedDeletions++;
                        log.warn("派生孤儿对象删除失败: errorType={}",
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

        return new DerivedAssetOrphanScanResult(
                true,
                scannedObjects,
                eligibleObjects,
                referencedObjects,
                orphanObjects,
                deletedObjects,
                failedDeletions,
                scannedPages,
                completed
        );
    }

    private Set<String> findReferencedKeys(String bucket, Set<String> candidateKeys) {
        if (candidateKeys.isEmpty()) {
            return Set.of();
        }
        Set<String> referencedKeys = new HashSet<>(
                fileObjectReferenceQuery.findReferencedObjectKeys(bucket, candidateKeys)
        );
        if (derivedObjectReferenceQueries != null) {
            for (DerivedObjectReferenceQuery query : derivedObjectReferenceQueries) {
                referencedKeys.addAll(query.findReferencedObjectKeys(bucket, candidateKeys));
            }
        }
        referencedKeys.addAll(readerPageAssetReferenceQuery.findReferencedObjectKeys(bucket, candidateKeys));
        referencedKeys.addAll(userAvatarObjectReferenceQuery.findReferencedObjectKeys(candidateKeys));
        referencedKeys.retainAll(candidateKeys);
        return referencedKeys;
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
            throw new IllegalStateException("派生对象扫描 pageSize 必须在 1 至 1000 之间");
        }
        if (properties.getMaximumPagesPerRun() < 1) {
            throw new IllegalStateException("派生对象扫描 maximumPagesPerRun 必须大于 0");
        }
        if (properties.getMaximumDeletesPerRun() < 1) {
            throw new IllegalStateException("派生对象扫描 maximumDeletesPerRun 必须大于 0");
        }
    }

    private void validatePositive(Duration value, String fieldName) {
        if (value == null || value.isZero() || value.isNegative()) {
            throw new IllegalStateException("派生对象扫描配置必须为正数: " + fieldName);
        }
    }
}
