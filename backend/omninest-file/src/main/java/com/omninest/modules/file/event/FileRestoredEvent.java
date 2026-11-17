package com.omninest.modules.file.event;

import java.time.Instant;
import java.util.UUID;

/**
 * 文件恢复后的索引重建事件。
 *
 * @param fileNodeId 文件节点 ID
 * @param ownerUserId 所有者用户 ID
 * @param fileName 文件名
 * @param restoredAt 恢复时间
 * @author OmniNest
 */
public record FileRestoredEvent(
        UUID fileNodeId,
        UUID ownerUserId,
        String fileName,
        Instant restoredAt
) {
}
