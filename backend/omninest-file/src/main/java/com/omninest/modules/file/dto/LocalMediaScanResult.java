package com.omninest.modules.file.dto;

import java.util.List;
import java.util.UUID;

/**
 * 本地媒体目录扫描结果。
 *
 * @param scannedCount 扫描文件数量
 * @param videoCount 视频数量
 * @param createdCount 新建引用数量
 * @param updatedCount 更新引用数量
 * @param missingCount 本次未发现数量
 * @param entries 当前可用视频文件的安全内容引用
 * @author OmniNest
 */
public record LocalMediaScanResult(
        int scannedCount,
        int videoCount,
        int createdCount,
        int updatedCount,
        int missingCount,
        List<LocalMediaScanEntry> entries
) {
    /**
     * 返回当前可用视频文件节点 ID，兼容仅关心文件标识的调用方。
     *
     * @return 文件节点 ID 列表
     */
    public List<UUID> fileNodeIds() {
        return entries.stream().map(LocalMediaScanEntry::fileNodeId).toList();
    }
}
