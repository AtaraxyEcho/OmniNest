package com.omninest.modules.file.event;

import java.util.UUID;

/**
 * 全站搜索索引重建任务事件。
 *
 * @param taskId 任务记录 ID
 * @param actorUserId 触发重建的管理员用户 ID
 */
public record SearchIndexRebuildEvent(UUID taskId, UUID actorUserId) {
}
