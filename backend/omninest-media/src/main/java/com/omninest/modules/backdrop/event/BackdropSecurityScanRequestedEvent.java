package com.omninest.modules.backdrop.event;

import java.util.UUID;

/**
 * 背景素材安全扫描任务消息。
 *
 * @param taskId 任务 ID
 * @param ownerUserId 所属用户 ID
 * @param assetId 素材 ID
 * @param ingressItemId 安全入库记录 ID
 * @param originalFileName 暂存对象原始文件名
 * @author OmniNest
 */
public record BackdropSecurityScanRequestedEvent(
        UUID taskId,
        UUID ownerUserId,
        UUID assetId,
        UUID ingressItemId,
        String originalFileName
) {
}
