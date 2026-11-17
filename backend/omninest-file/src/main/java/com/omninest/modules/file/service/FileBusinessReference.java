package com.omninest.modules.file.service;

import java.util.UUID;

/**
 * 文件节点的业务引用。
 *
 * @param module 模块编码
 * @param resourceType 业务资源类型
 * @param resourceId 业务资源 ID
 * @param fileNodeId 关联文件节点 ID
 * @author OmniNest
 */
public record FileBusinessReference(
        String module,
        String resourceType,
        UUID resourceId,
        UUID fileNodeId
) {
}
