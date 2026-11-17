package com.omninest.modules.file.dto;

import java.util.UUID;

/**
 * 已登记本地内容引用的最小业务描述。
 *
 * @param fileNodeId 文件节点 ID
 * @param relativePath 安全相对路径
 * @param providerEtag 快速版本标识
 * @param availabilityStatus 可用状态
 */
public record LocalMediaExistingRef(
        UUID fileNodeId,
        String relativePath,
        String providerEtag,
        String availabilityStatus
) {
}
