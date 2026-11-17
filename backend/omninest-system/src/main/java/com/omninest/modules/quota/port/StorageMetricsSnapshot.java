package com.omninest.modules.quota.port;

/**
 * 系统级存储指标快照。
 *
 * @param fileCount 文件节点数
 * @param folderCount 文件夹节点数
 * @param objectCount 文件对象数
 * @param usedBytes 文件对象总字节数
 * @author OmniNest
 */
public record StorageMetricsSnapshot(
        long fileCount,
        long folderCount,
        long objectCount,
        long usedBytes
) {
}
