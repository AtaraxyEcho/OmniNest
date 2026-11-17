package com.omninest.worker.storage;

/**
 * 单轮派生对象孤儿扫描结果。
 *
 * @param executed 是否获得锁并执行扫描
 * @param scannedObjects 已扫描对象数
 * @param eligibleObjects 超过年龄宽限的候选对象数
 * @param referencedObjects 有元数据引用的对象数
 * @param orphanObjects 未找到元数据引用的对象数
 * @param deletedObjects 已删除孤儿对象数
 * @param failedDeletions 删除失败对象数
 * @param scannedPages 已扫描页数
 * @param completed 是否完成当前存储桶全量扫描
 * @author OmniNest
 */
public record DerivedAssetOrphanScanResult(
        boolean executed,
        long scannedObjects,
        long eligibleObjects,
        long referencedObjects,
        long orphanObjects,
        long deletedObjects,
        long failedDeletions,
        int scannedPages,
        boolean completed
) {

    /**
     * 创建未获得执行锁的结果。
     *
     * @return 未执行结果
     */
    public static DerivedAssetOrphanScanResult skipped() {
        return new DerivedAssetOrphanScanResult(false, 0, 0, 0, 0, 0, 0, 0, false);
    }
}
