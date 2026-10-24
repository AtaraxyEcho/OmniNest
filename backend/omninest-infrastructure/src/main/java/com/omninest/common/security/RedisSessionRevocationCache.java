package com.omninest.common.security;

import java.time.Duration;
import java.util.Collection;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.TimeUnit;
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
    /** 旧版按用户存的 Set 无 TTL 时，迁移出的单会话键保留期。 */
    private static final Duration LEGACY_MIGRATION_TTL = Duration.ofDays(30);

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
            // 每个 sessionId 独立键：不同吊销来源的 TTL 互不覆盖，历史 sid 也能逐个过期。
            for (UUID sessionId : sessionIds) {
                redis.opsForValue().set(revokedKey(userId, sessionId), "1", ttl);
                // 未撤销判定必须同时作废，否则旧的 ok 标记会在自身 TTL 内压住这次撤销
                redis.delete(notRevokedKey(userId, sessionId));
            }
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
            if (Boolean.TRUE.equals(redis.hasKey(revokedKey(userId, sessionId)))) {
                return Optional.of(true);
            }
            // 滚动升级期旧版 Set 仍可能持有未过期的撤销项；命中后惰性迁移到单会话键，
            // 让旧 Set 自然过期，同时不把缓存命中率压到数据库。
            if (Boolean.TRUE.equals(redis.opsForSet().isMember(
                    legacySetKey(userId), sessionId.toString()))) {
                migrateLegacyRevocation(userId, sessionId);
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

    private void migrateLegacyRevocation(UUID userId, UUID sessionId) {
        try {
            Long remainingMillis = redis.getExpire(legacySetKey(userId), TimeUnit.MILLISECONDS);
            Duration ttl = remainingMillis != null && remainingMillis > 0
                    ? Duration.ofMillis(remainingMillis)
                    : LEGACY_MIGRATION_TTL;
            redis.opsForValue().set(revokedKey(userId, sessionId), "1", ttl);
        } catch (RuntimeException exception) {
            // 迁移只是优化；失败时仍按旧 Set 命中处理，撤销判定不受影响。
            log.debug("旧版会话撤销标记迁移失败: userId={}, errorType={}",
                    userId, exception.getClass().getSimpleName());
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

    private String revokedKey(UUID userId, UUID sessionId) {
        return BLACKLIST_PREFIX + userId + ":" + sessionId;
    }

    private String legacySetKey(UUID userId) {
        return BLACKLIST_PREFIX + userId;
    }

    private String notRevokedKey(UUID userId, UUID sessionId) {
        return NOT_REVOKED_PREFIX + userId + ":" + sessionId;
    }
}
