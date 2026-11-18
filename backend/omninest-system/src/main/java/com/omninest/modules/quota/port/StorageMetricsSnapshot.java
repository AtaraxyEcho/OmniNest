package com.omninest.modules.quota.port;

import java.util.List;

/**
 * 系统级存储指标快照。
 *
 * @param fileCount 文件节点数
 * @param folderCount 文件夹节点数
 * @param objectCount 文件对象数
 * @param usedBytes 文件对象总字节数
 * @param categoryBreakdown 按对象 MIME 分类的用量；条目字节和与 usedBytes 使用相同口径
 * @author OmniNest
 */
public record StorageMetricsSnapshot(
        long fileCount,
        long folderCount,
        long objectCount,
        long usedBytes,
        List<StorageCategoryMetric> categoryBreakdown
) {
    public StorageMetricsSnapshot(
            long fileCount,
            long folderCount,
            long objectCount,
            long usedBytes
    ) {
        this(fileCount, folderCount, objectCount, usedBytes, List.of());
    }

    public StorageMetricsSnapshot {
        categoryBreakdown = List.copyOf(categoryBreakdown);
    }
}
