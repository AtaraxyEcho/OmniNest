package com.omninest.common.security;

import java.time.Duration;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.TimeUnit;
import org.assertj.core.api.Assertions;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
import org.springframework.data.redis.core.SetOperations;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.ValueOperations;

/**
 * Redis 会话撤销缓存适配器测试。
 *
 * @author OmniNest
 */
class RedisSessionRevocationCacheTest {

    private StringRedisTemplate redis;
    private ValueOperations<String, String> valueOperations;
    private RedisSessionRevocationCache cache;

    @SuppressWarnings("unchecked")
    @BeforeEach
    void setUp() {
        redis = Mockito.mock(StringRedisTemplate.class);
        valueOperations = Mockito.mock(ValueOperations.class);
        Mockito.lenient().when(redis.opsForValue()).thenReturn(valueOperations);
        cache = new RedisSessionRevocationCache(redis);
    }

    @Test
    void markRevokedWritesIndependentKeyPerSession() {
        UUID userId = UUID.randomUUID();
        UUID firstSessionId = UUID.randomUUID();
        UUID secondSessionId = UUID.randomUUID();

        cache.markRevoked(
                userId,
                List.of(firstSessionId, secondSessionId),
                Duration.ofDays(30)
        );

        Mockito.verify(valueOperations).set(
                "session:blacklist:" + userId + ":" + firstSessionId,
                "1",
                Duration.ofDays(30)
        );
        Mockito.verify(valueOperations).set(
                "session:blacklist:" + userId + ":" + secondSessionId,
                "1",
                Duration.ofDays(30)
        );
        Mockito.verify(redis).delete("session:blacklist-ok:" + userId + ":" + firstSessionId);
        Mockito.verify(redis).delete("session:blacklist-ok:" + userId + ":" + secondSessionId);
    }

    @Test
    void containsReturnsCachedResult() {
        UUID userId = UUID.randomUUID();
        UUID sessionId = UUID.randomUUID();
        Mockito.when(redis.hasKey("session:blacklist:" + userId + ":" + sessionId))
                .thenReturn(Boolean.TRUE);

        boolean result = cache.contains(userId, sessionId);

        Assertions.assertThat(result).isTrue();
    }

    @Test
    @SuppressWarnings("unchecked")
    void checkRevokedFallsBackToLegacySetAndMigrates() {
        UUID userId = UUID.randomUUID();
        UUID sessionId = UUID.randomUUID();
        SetOperations<String, String> setOperations = Mockito.mock(SetOperations.class);
        Mockito.when(redis.opsForSet()).thenReturn(setOperations);
        Mockito.when(redis.hasKey("session:blacklist:" + userId + ":" + sessionId))
                .thenReturn(false);
        Mockito.when(setOperations.isMember("session:blacklist:" + userId, sessionId.toString()))
                .thenReturn(true);
        Mockito.when(redis.getExpire("session:blacklist:" + userId, TimeUnit.MILLISECONDS))
                .thenReturn(60_000L);

        Assertions.assertThat(cache.checkRevoked(userId, sessionId)).contains(true);
        Mockito.verify(valueOperations).set(
                "session:blacklist:" + userId + ":" + sessionId,
                "1",
                Duration.ofMillis(60_000)
        );
    }

    @Test
    void containsTreatsRedisFailureAsCacheMiss() {
        Mockito.when(redis.hasKey(Mockito.anyString()))
                .thenThrow(new IllegalStateException("Redis unavailable"));

        boolean result = cache.contains(UUID.randomUUID(), UUID.randomUUID());

        Assertions.assertThat(result).isFalse();
    }
}
