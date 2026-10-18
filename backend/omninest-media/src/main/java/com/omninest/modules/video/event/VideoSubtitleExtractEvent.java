package com.omninest.modules.video.event;

import com.omninest.modules.video.domain.MediaVideoItem;

/**
 * 内嵌字幕异步提取请求，由探测入口在请求线程外触发提取。
 */
public record VideoSubtitleExtractEvent(MediaVideoItem item) {
}
