package com.omninest.modules.photos.event;

import java.util.UUID;

/**
 * 用户删除后的照片共享索引清理事件。
 *
 * <p>照片索引是跨用户的共享 Lucene 卷、由 Worker 独占写入，请求进程不能直接删盘，
 * 只能投递事件由 Worker 在本进程内删除。</p>
 *
 * @param ownerUserId 被删除的用户 ID
 * @author OmniNest
 */
public record PhotoIndexUserPurgeEvent(UUID ownerUserId) {
}
