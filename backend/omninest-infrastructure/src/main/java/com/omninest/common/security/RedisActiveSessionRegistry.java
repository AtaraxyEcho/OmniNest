package com.omninest.common.security;

import java.time.Duration;
import java.util.Optional;
import java.util.UUID;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Component;

/**
 * 使用 Redis 注册用户各客户端平台的活动会话。
 *
 * <p>Redis 查询失败时回退到持久层端口查询，避免同平台互斥在 Redis 故障期间静默失效；
 * 无可用回退实现（如裁剪部署）时保持空结果并记录告警。
 *
 * @author OmniNest
 */
@Slf4j
@Component
public class RedisActiveSessionRegistry implements ActiveSessionRegistry {

    private static final String ACTIVE_PREFIX = "session:active:";

    private final StringRedisTemplate redis;
    private final ObjectProvider<ActiveSessionFallbackLookup> fallbackLookup;

    public RedisActiveSessionRegistry(
            StringRedisTemplate redis,
            ObjectProvider<ActiveSessionFallbackLookup> fallbackLookup
    ) {
        this.redis = redis;
        this.fallbackLookup = fallbackLookup;
    }

    /**
     * {@inheritDoc}
     */
    @Override
    public void register(UUID userId, String platform, UUID sessionId, Duration ttl) {
        try {
            redis.opsForValue().set(key(userId, platform), sessionId.toString(), ttl);
        } catch (RuntimeException exception) {
            log.warn("Redis 活动会话写入失败: userId={}, platform={}", userId, platform, exception);
        }
    }

    /**
     * {@inheritDoc}
     */
    @Override
    public Optional<UUID> find(UUID userId, String platform) {
        try {
            String sessionId = redis.opsForValue().get(key(userId, platform));
            if (sessionId == null) {
                // 键缺失无法区分“无会话”与“Redis 丢失/写失败”：咨询持久层回退，
                // 覆盖 Redis 重启清空或 register 写失败导致的互斥失联窗口
                ActiveSessionFallbackLookup fallback = fallbackLookup.getIfAvailable();
                if (fallback != null) {
                    return fallback.findActiveSessionId(userId, platform);
                }
                return Optional.empty();
            }
            return Optional.of(UUID.fromString(sessionId));
        } catch (RuntimeException exception) {
            ActiveSessionFallbackLookup fallback = fallbackLookup.getIfAvailable();
            if (fallback != null) {
                log.warn("Redis 活动会话查询失败，回退数据库: userId={}, platform={}", userId, platform, exception);
                return fallback.findActiveSessionId(userId, platform);
            }
            log.warn("Redis 活动会话查询失败且无回退实现: userId={}, platform={}", userId, platform, exception);
            return Optional.empty();
        }
    }

    private String key(UUID userId, String platform) {
        return ACTIVE_PREFIX + userId + ":" + platform;
    }
}
