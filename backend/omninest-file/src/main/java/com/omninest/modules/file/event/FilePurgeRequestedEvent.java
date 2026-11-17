package com.omninest.modules.file.event;

import java.util.UUID;

/**
 * 文件永久删除任务消息。
 *
 * @param taskId 任务 ID
 * @param ownerUserId 所属用户 ID
 * @param rootFileNodeId 根文件节点 ID
 * @author OmniNest
 */
public record FilePurgeRequestedEvent(UUID taskId, UUID ownerUserId, UUID rootFileNodeId) {
}
