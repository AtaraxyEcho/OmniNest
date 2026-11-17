package com.omninest.modules.file.dto;

import java.time.Instant;

/**
 * File 模块向业务模块暴露的本地媒体发现结果。
 *
 * @param relativePath 存储位置根目录内安全相对路径
 * @param fileName 文件名
 * @param sizeBytes 文件大小
 * @param modifiedAt 修改时间
 * @param providerEtag 快速版本标识
 */
public record LocalMediaDiscoveredFile(
        String relativePath,
        String fileName,
        long sizeBytes,
        Instant modifiedAt,
        String providerEtag
) {
}
