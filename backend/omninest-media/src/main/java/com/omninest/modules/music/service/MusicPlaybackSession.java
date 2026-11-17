package com.omninest.modules.music.service;

import java.time.Instant;
import java.util.UUID;

/**
 * 音乐播放短期会话。
 *
 * @author OmniNest
 * @param sessionId 会话标识
 * @param ownerUserId 拥有者用户 ID
 * @param trackId 本地曲目 ID，在线播放时为空
 * @param sourceType 播放来源类型
 * @param sourcePlatform 在线来源平台，本地播放时为空
 * @param sourceUrl 后端解析后的真实音源地址
 * @param expiresAt 会话过期时间
 * @param durationSeconds 曲目时长
 * @param format 音频格式
 */
public record MusicPlaybackSession(
        String sessionId,
        UUID ownerUserId,
        UUID trackId,
        MusicPlaybackSourceType sourceType,
        String sourcePlatform,
        String sourceUrl,
        Instant expiresAt,
        Integer durationSeconds,
        String format
) {
}
