package com.omninest.modules.video.event;

import java.util.UUID;

/**
 * 用户确认候选后的本地媒体入库请求。
 *
 * @param taskId 任务 ID
 * @param ownerUserId 媒体目录所有者用户 ID；后台任务的发起操作人由任务记录单独保存
 * @param sourceId 来源 ID
 * @param scanRunId 发现运行 ID
 */
public record LocalVideoLibraryApplyRequestedEvent(
        UUID taskId,
        UUID ownerUserId,
        UUID sourceId,
        UUID scanRunId
) {
}
