package com.omninest.modules.photos.event;

import java.util.UUID;

/**
 * 动态照片存量回扫异步任务事件。
 *
 * @param taskId 通用任务标识
 * @param ownerUserId 照片所有者
 * @author OmniNest
 */
public record PhotoMotionRescanEvent(
        UUID taskId,
        UUID ownerUserId
) {
}
