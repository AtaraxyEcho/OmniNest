package com.omninest.modules.music.service;

import com.omninest.modules.music.dto.MusicDtos.MusicPlaybackPlanDto;
import java.time.Duration;
import java.time.Instant;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

/**
 * 音乐播放短期会话服务。
 *
 * <p>会话体做进程内短缓存以消除 Range 请求上的 Redis 往返；令牌仍每次校验，
 * 缓存 TTL 不超过会话过期时间。</p>
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class MusicPlaybackSessionService {
    private static final Duration DEFAULT_TOKEN_TTL = Duration.ofMinutes(10);
    private static final Duration LOCAL_SESSION_CACHE_TTL = Duration.ofSeconds(30);

    /** 进程内会话缓存容量上限，超出时淘汰最早过期条目。 */
    private static final int LOCAL_SESSION_CACHE_MAX_ENTRIES = 2048;

    private final MusicPlaybackTokenService tokenService;
    private final MusicPlaybackSessionStore sessionStore;
    private final ConcurrentHashMap<String, CachedSession> localSessions = new ConcurrentHashMap<>();

    private record CachedSession(MusicPlaybackSession session, long expireAtMillis) {
        private boolean expired() {
            return System.currentTimeMillis() >= expireAtMillis;
        }
    }

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
     * <p>会话载荷可走本地缓存；<strong>令牌必须对每次传入的 token 做校验</strong>，
     * 不得因缓存命中而跳过 HMAC 验证。</p>
     *
     * @param sessionId 会话标识
     * @param token 播放令牌
     * @return 会话存在且令牌有效时返回会话
     */
    public Optional<MusicPlaybackSession> resolve(String sessionId, String token) {
        Instant now = Instant.now();
        MusicPlaybackSession session = findSession(sessionId, now);
        if (session == null) {
            return Optional.empty();
        }
        if (!tokenService.verify(token, sessionId, session.expiresAt(), now)) {
            localSessions.remove(sessionId);
            return Optional.empty();
        }
        return Optional.of(session);
    }

    private MusicPlaybackSession findSession(String sessionId, Instant now) {
        CachedSession cached = localSessions.get(sessionId);
        if (cached != null && !cached.expired() && now.isBefore(cached.session().expiresAt())) {
            return cached.session();
        }
        if (cached != null) {
            localSessions.remove(sessionId, cached);
        }
        MusicPlaybackSession session = sessionStore.find(sessionId).orElse(null);
        if (session == null) {
            return null;
        }
        if (now.isAfter(session.expiresAt())) {
            sessionStore.delete(sessionId);
            localSessions.remove(sessionId);
            return null;
        }
        Duration remaining = Duration.between(now, session.expiresAt());
        long ttlMillis = Math.min(LOCAL_SESSION_CACHE_TTL.toMillis(), remaining.toMillis());
        if (ttlMillis > 0) {
            localSessions.put(sessionId, new CachedSession(session, System.currentTimeMillis() + ttlMillis));
            evictLocalSessionsIfNeeded();
        }
        return session;
    }

    private void evictLocalSessionsIfNeeded() {
        if (localSessions.size() <= LOCAL_SESSION_CACHE_MAX_ENTRIES) {
            return;
        }
        localSessions.entrySet().removeIf(entry -> entry.getValue().expired());
        if (localSessions.size() <= LOCAL_SESSION_CACHE_MAX_ENTRIES) {
            return;
        }
        localSessions.entrySet().stream()
                .sorted((a, b) -> Long.compare(a.getValue().expireAtMillis, b.getValue().expireAtMillis))
                .limit(localSessions.size() - LOCAL_SESSION_CACHE_MAX_ENTRIES)
                .map(entry -> entry.getKey())
                .toList()
                .forEach(localSessions::remove);
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
