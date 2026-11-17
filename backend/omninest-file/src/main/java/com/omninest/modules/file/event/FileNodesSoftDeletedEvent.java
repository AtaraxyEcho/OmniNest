package com.omninest.modules.file.event;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

/**
 * 文件软删除事件。发布于文件移入回收站时，供关联模块刷新资源可见性。
 *
 * @param ownerUserId  所属用户
 * @param fileNodeIds  被软删除的文件节点 ID 列表
 * @param occurredAt   事件时间
 * @author OmniNest
 */
public record FileNodesSoftDeletedEvent(
        UUID ownerUserId,
        List<UUID> fileNodeIds,
        Instant occurredAt
) {
}
