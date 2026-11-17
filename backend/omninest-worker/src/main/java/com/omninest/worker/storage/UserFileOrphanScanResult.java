package com.omninest.worker.storage;

/**
 * 单轮原件存储桶孤儿对象扫描结果。
 *
 * @param executed 是否获得锁并执行扫描
 * @param scannedObjects 已扫描对象数
 * @param eligibleObjects 超过年龄宽限的候选对象数
 * @param referencedObjects 存在文件对象元数据行的对象数
 * @param ingressHeldObjects 由在途入库记录持有的对象数
 * @param orphanObjects 既无元数据行也无在途会话的对象数
 * @param orphanBytes 孤儿对象字节数
 * @param deletedObjects 已删除孤儿对象数
 * @param deletedBytes 已删除孤儿对象字节数
 * @param failedDeletions 删除失败对象数
 * @param scannedPages 已扫描页数
 * @param completed 是否完成当前存储桶全量扫描
 * @author OmniNest
 */
public record UserFileOrphanScanResult(
        boolean executed,
        long scannedObjects,
        long eligibleObjects,
        long referencedObjects,
        long ingressHeldObjects,
        long orphanObjects,
        long orphanBytes,
        long deletedObjects,
        long deletedBytes,
        long failedDeletions,
        int scannedPages,
        boolean completed
) {

    /**
     * 创建未获得执行锁的结果。
     *
     * @return 未执行结果
     */
    public static UserFileOrphanScanResult skipped() {
        return new UserFileOrphanScanResult(false, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, false);
    }
}
