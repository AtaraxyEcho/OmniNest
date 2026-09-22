package com.omninest.modules.music.service;

import com.omninest.modules.music.dto.MusicDtos.MusicPlaybackPlanDto;
import java.time.Duration;
import java.time.Instant;
import java.util.Optional;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

/**
 * 音乐播放短期会话服务。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class MusicPlaybackSessionService {
    private static final Duration DEFAULT_TOKEN_TTL = Duration.ofMinutes(10);
    private final MusicPlaybackTokenService tokenService;
    private final MusicPlaybackSessionStore sessionStore;

    /**
     * 创建本地曲库播放计划。
     *
     * @param ownerUserId 用户 ID
     * @param trackId 曲目 ID
     * @param sourceUrl 真实音源地址
     * @param sourceExpiresAt 真实音源过期时间
     * @param durationSeconds 曲目时长
     * @param format 音频格式
     * @return 播放计划
     */
    public MusicPlaybackPlanDto createLocalPlan(
            UUID ownerUserId,
            UUID trackId,
            String sourceUrl,
            Instant sourceExpiresAt,
            Integer durationSeconds,
            String format
    ) {
        return createPlan(ownerUserId, trackId, MusicPlaybackSourceType.LOCAL, null, sourceUrl, sourceExpiresAt,
                durationSeconds, format);
    }

    /**
     * 创建在线播放计划。
     *
     * @param ownerUserId 用户 ID
     * @param sourcePlatform 在线来源平台
     * @param sourceUrl 真实音源地址
     * @param durationSeconds 曲目时长
     * @param format 音频格式
     * @return 播放计划
     */
    public MusicPlaybackPlanDto createOnlinePlan(
            UUID ownerUserId,
            String sourcePlatform,
            String sourceUrl,
            Integer durationSeconds,
            String format
    ) {
        return createPlan(
                ownerUserId,
                null,
                MusicPlaybackSourceType.ONLINE,
                sourcePlatform,
                sourceUrl,
                null,
                durationSeconds,
                format
        );
    }

    /**
     * 解析播放会话。
     *
     * @param sessionId 会话标识
     * @param token 播放令牌
     * @return 会话存在且令牌有效时返回会话
     */
    public Optional<MusicPlaybackSession> resolve(String sessionId, String token) {
        MusicPlaybackSession session = sessionStore.find(sessionId).orElse(null);
        Instant now = Instant.now();
        if (session == null) {
            return Optional.empty();
        }
        if (now.isAfter(session.expiresAt())) {
            sessionStore.delete(sessionId);
            return Optional.empty();
        }
        if (!tokenService.verify(token, sessionId, session.expiresAt(), now)) {
            return Optional.empty();
        }
        return Optional.of(session);
    }

    private MusicPlaybackPlanDto createPlan(
            UUID ownerUserId,
            UUID trackId,
            MusicPlaybackSourceType sourceType,
            String sourcePlatform,
            String sourceUrl,
            Instant sourceExpiresAt,
            Integer durationSeconds,
            String format
    ) {
        String sessionId = UUID.randomUUID().toString();
        Instant expiresAt = resolveExpiresAt(sourceExpiresAt);
        MusicPlaybackSession session = new MusicPlaybackSession(
                sessionId,
                ownerUserId,
                trackId,
                sourceType,
                sourcePlatform,
                sourceUrl,
                expiresAt,
                durationSeconds,
                format
        );
        sessionStore.save(session);
        String token = tokenService.sign(sessionId, expiresAt);
        String url = "/api/v1/music/playback/sessions/" + sessionId + "/stream?token=" + token;
        return new MusicPlaybackPlanDto(trackId, url, expiresAt, durationSeconds, format, null);
    }

    private Instant resolveExpiresAt(Instant sourceExpiresAt) {
        Instant defaultExpiresAt = Instant.now().plus(DEFAULT_TOKEN_TTL);
        if (sourceExpiresAt == null || sourceExpiresAt.isAfter(defaultExpiresAt)) {
            return defaultExpiresAt;
        }
        return sourceExpiresAt;
    }
}
