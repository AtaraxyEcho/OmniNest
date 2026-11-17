package com.omninest.modules.file.service;

import java.util.List;
import java.util.UUID;

/**
 * 文件永久删除参与者上下文。
 *
 * @param taskId 任务 ID
 * @param ownerUserId 所属用户 ID
 * @param rootFileNodeId 根文件节点 ID
 * @param fileNodeIds 当前目标文件节点 ID
 * @author OmniNest
 */
public record PurgeContext(
        UUID taskId,
        UUID ownerUserId,
        UUID rootFileNodeId,
        List<UUID> fileNodeIds
) {
    public PurgeContext {
        fileNodeIds = List.copyOf(fileNodeIds);
    }
}
