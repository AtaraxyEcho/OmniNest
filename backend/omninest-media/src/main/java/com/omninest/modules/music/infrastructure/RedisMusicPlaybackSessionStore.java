package com.omninest.modules.music.infrastructure;

import com.github.benmanes.caffeine.cache.Cache;
import com.github.benmanes.caffeine.cache.Caffeine;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.json.JsonSupport;
import com.omninest.common.util.RedisUtil;
import com.omninest.modules.music.service.MusicPlaybackSession;
import com.omninest.modules.music.service.MusicPlaybackSessionStore;
import java.time.Duration;
import java.time.Instant;
import java.util.Optional;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.core.env.Environment;
import org.springframework.core.env.Profiles;
import org.springframework.stereotype.Component;

/**
 * 使用 Redis 共享播放会话，并在非生产环境的 Redis 故障期间使用进程内缓存降级。
 *
 * @author OmniNest
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class RedisMusicPlaybackSessionStore implements MusicPlaybackSessionStore {
    private static final String KEY_PREFIX = "omninest:music:playback:session:";
    private static final Duration FALLBACK_TTL = Duration.ofMinutes(30);
    private static final long MAX_FALLBACK_SESSION_COUNT = 20_000L;

    private final RedisUtil redisUtil;
    private final Environment environment;
    private final Cache<String, MusicPlaybackSession> fallback = Caffeine.newBuilder()
            .expireAfterWrite(FALLBACK_TTL)
            .maximumSize(MAX_FALLBACK_SESSION_COUNT)
            .build();

    /**
     * 保存播放会话。
     *
     * @param session 播放会话
     */
    @Override
    public void save(MusicPlaybackSession session) {
        Duration ttl = Duration.between(Instant.now(), session.expiresAt());
        if (ttl.isZero() || ttl.isNegative()) {
            return;
        }
        try {
            redisUtil.set(key(session.sessionId()), JsonSupport.toJson(session), ttl);
        } catch (RuntimeException exception) {
            requireNonProductionFallback("写入音乐播放会话失败");
            log.warn("写入音乐播放会话 Redis 失败，使用进程内缓存降级: sessionId={}", session.sessionId());
        }
        if (!isProduction()) {
            fallback.put(session.sessionId(), session);
        }
    }

    /**
     * 查询播放会话。
     *
     * @param sessionId 会话标识
     * @return 播放会话
     */
    @Override
    public Optional<MusicPlaybackSession> find(String sessionId) {
        try {
            String payload = redisUtil.get(key(sessionId));
            if (payload != null && !payload.isBlank()) {
                MusicPlaybackSession session = JsonSupport.fromJson(payload, MusicPlaybackSession.class);
                if (!isProduction()) {
                    fallback.put(sessionId, session);
                }
                return Optional.of(session);
            }
        } catch (RuntimeException exception) {
            requireNonProductionFallback("读取音乐播放会话失败");
            log.warn("读取音乐播放会话 Redis 失败，尝试进程内缓存: sessionId={}", sessionId);
        }
        if (isProduction()) {
            return Optional.empty();
        }
        return Optional.ofNullable(fallback.getIfPresent(sessionId));
    }

    /**
     * 删除播放会话。
     *
     * @param sessionId 会话标识
     */
    @Override
    public void delete(String sessionId) {
        fallback.invalidate(sessionId);
        try {
            redisUtil.delete(key(sessionId));
        } catch (RuntimeException exception) {
            log.warn("删除音乐播放会话 Redis 记录失败: sessionId={}", sessionId);
        }
    }

    private String key(String sessionId) {
        return KEY_PREFIX + sessionId;
    }

    private void requireNonProductionFallback(String message) {
        if (isProduction()) {
            throw new BusinessException(ErrorCode.INTERNAL_ERROR, message);
        }
    }

    private boolean isProduction() {
        return environment.acceptsProfiles(Profiles.of("prod"));
    }
}
