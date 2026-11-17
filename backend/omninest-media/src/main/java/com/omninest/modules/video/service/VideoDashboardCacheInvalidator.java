package com.omninest.modules.video.service;

import com.omninest.common.cache.ReadThroughCache;
import com.omninest.modules.media.domain.MediaPlaybackType;
import com.omninest.modules.media.event.MediaProgressChangedEvent;
import lombok.RequiredArgsConstructor;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;

/**
 * 监听播放进度变化并失效视频仪表盘缓存，保证继续观看列表与统计及时刷新。
 *
 * @author OmniNest
 */
@Component
@RequiredArgsConstructor
public class VideoDashboardCacheInvalidator {
    private final ReadThroughCache readThroughCache;

    /**
     * 处理视频播放进度变化事件。
     *
     * @param event 播放进度变化事件
     */
    @EventListener
    public void onProgressChanged(MediaProgressChangedEvent event) {
        if (event.mediaType() != MediaPlaybackType.VIDEO) {
            return;
        }
        readThroughCache.invalidate("omninest:dashboard:video:" + event.ownerUserId());
    }
}
