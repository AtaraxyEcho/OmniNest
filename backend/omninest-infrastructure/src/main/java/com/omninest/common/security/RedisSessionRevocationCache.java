package com.omninest.common.security;

import java.time.Duration;
import java.util.Collection;
import java.util.Optional;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Component;

/**
 * 使用 Redis 保存会话撤销黑名单与短期「经数据库确认未撤销」判定。
 *
 * @author OmniNest
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class RedisSessionRevocationCache implements SessionRevocationCache {

    private static final String BLACKLIST_PREFIX = "session:blacklist:";
    private static final String NOT_REVOKED_PREFIX = "session:blacklist-ok:";

    private final StringRedisTemplate redis;

    /**
     * {@inheritDoc}
     */
    @Override
    public void markRevoked(UUID userId, Collection<UUID> sessionIds, Duration ttl) {
        if (sessionIds == null || sessionIds.isEmpty()) {
            return;
        }
        try {
            String key = BLACKLIST_PREFIX + userId;
            String[] values = sessionIds.stream().map(UUID::toString).toArray(String[]::new);
            redis.opsForSet().add(key, values);
            redis.expire(key, ttl);
            // 未撤销判定必须同时作废，否则旧的 ok 标记会在自身 TTL 内压住这次撤销
            sessionIds.forEach(sessionId -> redis.delete(notRevokedKey(userId, sessionId)));
        } catch (RuntimeException exception) {
            log.warn("Redis 会话撤销缓存写入失败: userId={}, count={}", userId, sessionIds.size(), exception);
        }
    }

    /**
     * {@inheritDoc}
     */
    @Override
    public boolean contains(UUID userId, UUID sessionId) {
        return checkRevoked(userId, sessionId).orElse(false);
    }

    /**
     * {@inheritDoc}
     */
    @Override
    public Optional<Boolean> checkRevoked(UUID userId, UUID sessionId) {
        try {
            if (Boolean.TRUE.equals(redis.opsForSet().isMember(BLACKLIST_PREFIX + userId, sessionId.toString()))) {
                return Optional.of(true);
            }
            if (Boolean.TRUE.equals(redis.hasKey(notRevokedKey(userId, sessionId)))) {
                return Optional.of(false);
            }
            return Optional.empty();
        } catch (RuntimeException exception) {
            log.warn("Redis 会话撤销缓存查询失败: userId={}", userId, exception);
            return Optional.empty();
        }
    }

    /**
     * {@inheritDoc}
     */
    @Override
    public void markNotRevoked(UUID userId, UUID sessionId, Duration ttl) {
        try {
            redis.opsForValue().set(notRevokedKey(userId, sessionId), "1", ttl);
        } catch (RuntimeException exception) {
            log.warn("Redis 会话未撤销标记写入失败: userId={}, sessionId={}", userId, sessionId, exception);
        }
    }

    private String notRevokedKey(UUID userId, UUID sessionId) {
        return NOT_REVOKED_PREFIX + userId + ":" + sessionId;
    }
}
