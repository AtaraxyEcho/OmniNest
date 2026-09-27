package com.omninest.common.config;

import java.time.Duration;
import java.util.Optional;
import org.assertj.core.api.Assertions;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.ValueOperations;

/**
 * Redis 运行时配置缓存适配器测试。
 *
 * @author OmniNest
 */
class RedisRuntimeConfigCacheTest {

    private StringRedisTemplate redisTemplate;
    private ValueOperations<String, String> valueOperations;
    private RedisRuntimeConfigCache cache;

    @SuppressWarnings("unchecked")
    @BeforeEach
    void setUp() {
        redisTemplate = Mockito.mock(StringRedisTemplate.class);
        valueOperations = Mockito.mock(ValueOperations.class);
        Mockito.when(redisTemplate.opsForValue()).thenReturn(valueOperations);
        cache = new RedisRuntimeConfigCache(redisTemplate);
    }

    @Test
    void getReturnsCachedValue() {
        Mockito.when(valueOperations.get("omninest:config:music.quality"))
                .thenReturn("lossless");

        Optional<String> value = cache.get("music.quality");

        Assertions.assertThat(value).contains("lossless");
    }

    @Test
    void putUsesConfiguredExpiration() {
        cache.put("music.quality", "lossless");

        Mockito.verify(valueOperations).set(
                "omninest:config:music.quality",
                "lossless",
                Duration.ofMinutes(5)
        );
    }

    @Test
    void evictDeletesNamespacedKey() {
        cache.evict("music.quality");

        Mockito.verify(redisTemplate).delete("omninest:config:music.quality");
    }

    @Test
    void getTreatsRedisFailureAsCacheMiss() {
        Mockito.when(redisTemplate.opsForValue())
                .thenThrow(new IllegalStateException("Redis unavailable"));

        Optional<String> value = cache.get("music.quality");

        Assertions.assertThat(value).isEmpty();
    }

    @Test
    void secondGetServesLocalCacheWithoutRedis() {
        Mockito.when(valueOperations.get("omninest:config:music.quality"))
                .thenReturn("lossless");

        cache.get("music.quality");
        cache.get("music.quality");

        Mockito.verify(valueOperations, Mockito.times(1)).get("omninest:config:music.quality");
    }

    @Test
    void evictClearsLocalCache() {
        Mockito.when(valueOperations.get("omninest:config:music.quality"))
                .thenReturn("lossless");
        cache.get("music.quality");

        cache.evict("music.quality");
        cache.get("music.quality");

        Mockito.verify(valueOperations, Mockito.times(2)).get("omninest:config:music.quality");
    }
}
