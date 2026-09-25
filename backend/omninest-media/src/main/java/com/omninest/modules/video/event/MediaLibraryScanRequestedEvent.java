package com.omninest.modules.video.event;

import java.util.UUID;

/**
 * 用户媒体库扫描请求事件。
 *
 * @param taskId 任务 ID
 * @param ownerUserId 媒体目录所有者用户 ID
 * @param rootFolderId 根文件夹 ID，可为空
 * @param incremental 是否增量扫描
 * @author OmniNest
 */
public record MediaLibraryScanRequestedEvent(
        UUID taskId,
        UUID ownerUserId,
        UUID rootFolderId,
        boolean incremental
) {
}
