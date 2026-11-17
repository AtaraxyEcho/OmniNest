package com.omninest.modules.media.event;

import com.omninest.modules.media.domain.MediaPlaybackType;
import java.util.UUID;

/**
 * 播放进度发生变化事件，用于跨模块通知各业务模块失效依赖进度的派生数据。
 *
 * @param ownerUserId 进度所有者用户 ID
 * @param mediaType 媒体类型
 */
public record MediaProgressChangedEvent(
        UUID ownerUserId,
        MediaPlaybackType mediaType
) {
}
