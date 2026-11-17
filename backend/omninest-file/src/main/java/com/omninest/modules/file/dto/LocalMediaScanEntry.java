package com.omninest.modules.file.dto;

import java.util.UUID;

/**
 * 本地媒体扫描发现的安全内容引用。
 *
 * <p>相对路径始终以存储位置为根，不包含宿主机绝对路径。</p>
 *
 * @param fileNodeId 文件节点 ID
 * @param relativePath 存储位置内的相对路径
 * @param fileName 文件名
 * @author OmniNest
 */
public record LocalMediaScanEntry(
        UUID fileNodeId,
        String relativePath,
        String fileName
) {
}
