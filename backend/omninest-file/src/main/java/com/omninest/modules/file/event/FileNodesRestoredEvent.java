package com.omninest.modules.file.event;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

/**
 * 文件节点恢复事件，供提交后的索引修复和事务内媒体可见性同步使用。
 *
 * @param ownerUserId 文件所有者用户 ID
 * @param fileNodeIds 恢复的文件节点 ID
 * @param occurredAt 事件发生时间
 * @author OmniNest
 */
public record FileNodesRestoredEvent(
        UUID ownerUserId,
        List<UUID> fileNodeIds,
        Instant occurredAt
) {
}
