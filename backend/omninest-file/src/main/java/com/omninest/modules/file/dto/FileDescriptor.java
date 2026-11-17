package com.omninest.modules.file.dto;

import com.omninest.modules.file.domain.SpaceType;
import java.time.Instant;
import java.util.UUID;

/**
 * 跨模块使用的不可变文件节点描述符。
 *
 * @param id 文件节点 ID
 * @param ownerUserId 所有者用户 ID
 * @param parentId 父节点 ID
 * @param nodeType 节点类型
 * @param name 文件名
 * @param normalizedPath 规范化路径
 * @param mimeType MIME 类型
 * @param sizeBytes 文件字节数
 * @param currentObjectId 当前文件对象 ID
 * @param sourceType 来源类型
 * @param deleted 是否已删除
 * @param shared 是否开启共享
 * @param spaceType 空间类型
 * @param uploadedBy 上传者用户 ID
 * @param createdAt 创建时间
 * @param updatedAt 更新时间
 * @author OmniNest
 */
public record FileDescriptor(
        UUID id,
        UUID ownerUserId,
        UUID parentId,
        String nodeType,
        String name,
        String normalizedPath,
        String mimeType,
        long sizeBytes,
        UUID currentObjectId,
        String sourceType,
        boolean deleted,
        boolean shared,
        SpaceType spaceType,
        UUID uploadedBy,
        Instant createdAt,
        Instant updatedAt
) {
}
