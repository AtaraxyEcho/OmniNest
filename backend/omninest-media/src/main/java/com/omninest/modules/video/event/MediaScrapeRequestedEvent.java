package com.omninest.modules.video.event;

import java.util.UUID;

/**
 * 影视元数据刮削请求事件。
 *
 * <p>{@code provider} 与 {@code externalId} 非空表示用户在候选列表里指定了具体条目：
 * 执行端只接受该候选，不再按标题取首个搜索结果；两者为空时保持原有自动匹配行为。</p>
 *
 * @author OmniNest
 */
public record MediaScrapeRequestedEvent(
        UUID taskId,
        UUID ownerUserId,
        UUID fileNodeId,
        String title,
        Integer year,
        Integer seasonNumber,
        Integer episodeNumber,
        boolean force,
        String provider,
        String externalId
) {
}
