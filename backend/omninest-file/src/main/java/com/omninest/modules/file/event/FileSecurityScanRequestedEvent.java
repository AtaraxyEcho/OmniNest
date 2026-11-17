package com.omninest.modules.file.event;

import java.util.UUID;

/**
 * 文件安全扫描任务消息。
 *
 * @param taskId 任务 ID
 * @param ownerUserId 所属用户 ID
 * @param ingressItemId 安全入库记录 ID
 * @param asVersionOfFileId 版本上传目标文件节点 ID，可为空
 * @param declaredSha256 客户端声明的文件摘要，可为空
 * @author OmniNest
 */
public record FileSecurityScanRequestedEvent(
        UUID taskId,
        UUID ownerUserId,
        UUID ingressItemId,
        UUID asVersionOfFileId,
        String declaredSha256
) {
}
