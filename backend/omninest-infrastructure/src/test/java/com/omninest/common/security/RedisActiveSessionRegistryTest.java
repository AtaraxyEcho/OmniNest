package com.omninest.common.security;

import java.time.Duration;
import java.util.Optional;
import java.util.UUID;
import org.assertj.core.api.Assertions;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.ValueOperations;

/**
 * Redis 活动会话注册适配器测试。
 *
 * @author OmniNest
 */
class RedisActiveSessionRegistryTest {

    private StringRedisTemplate redis;
    private ValueOperations<String, String> valueOperations;
    private org.springframework.beans.factory.ObjectProvider<ActiveSessionFallbackLookup> fallbackProvider;
    private RedisActiveSessionRegistry registry;

    @SuppressWarnings("unchecked")
    @BeforeEach
    void setUp() {
        redis = Mockito.mock(StringRedisTemplate.class);
        valueOperations = Mockito.mock(ValueOperations.class);
        Mockito.when(redis.opsForValue()).thenReturn(valueOperations);
        fallbackProvider = Mockito.mock(org.springframework.beans.factory.ObjectProvider.class);
        registry = new RedisActiveSessionRegistry(redis, fallbackProvider);
    }

    @Test
    void registerWritesPlatformSession() {
        UUID userId = UUID.randomUUID();
        UUID sessionId = UUID.randomUUID();
        Duration ttl = Duration.ofDays(7);

        registry.register(userId, "android", sessionId, ttl);

        Mockito.verify(valueOperations).set(
                "session:active:" + userId + ":android",
                sessionId.toString(),
                ttl
        );
    }

    @Test
    void findReturnsRegisteredSession() {
        UUID userId = UUID.randomUUID();
        UUID sessionId = UUID.randomUUID();
        Mockito.when(valueOperations.get("session:active:" + userId + ":desktop"))
                .thenReturn(sessionId.toString());

        Optional<UUID> result = registry.find(userId, "desktop");

        Assertions.assertThat(result).contains(sessionId);
    }

    @Test
    void findReturnsEmptyWhenRedisFails() {
        Mockito.when(redis.opsForValue()).thenThrow(new IllegalStateException("Redis unavailable"));

        Optional<UUID> result = registry.find(UUID.randomUUID(), "web");

        Assertions.assertThat(result).isEmpty();
    }

    @Test
    void findFallsBackToPersistentLookupWhenRedisFails() {
        UUID userId = UUID.randomUUID();
        UUID sessionId = UUID.randomUUID();
        Mockito.when(valueOperations.get("session:active:" + userId + ":web"))
                .thenThrow(new IllegalStateException("redis down"));
        ActiveSessionFallbackLookup fallback = (uid, platform) -> Optional.of(sessionId);
        Mockito.when(fallbackProvider.getIfAvailable()).thenReturn(fallback);

        Optional<UUID> result = registry.find(userId, "web");

        Assertions.assertThat(result).contains(sessionId);
    }

    @Test
    void findReturnsEmptyWhenRedisFailsWithoutFallback() {
        UUID userId = UUID.randomUUID();
        Mockito.when(valueOperations.get("session:active:" + userId + ":web"))
                .thenThrow(new IllegalStateException("redis down"));
        Mockito.when(fallbackProvider.getIfAvailable()).thenReturn(null);

        Optional<UUID> result = registry.find(userId, "web");

        Assertions.assertThat(result).isEmpty();
    }
}
