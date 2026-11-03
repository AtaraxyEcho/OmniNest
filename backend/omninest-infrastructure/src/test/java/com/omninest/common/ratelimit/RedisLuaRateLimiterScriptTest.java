package com.omninest.common.ratelimit;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;

import java.time.Duration;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.data.redis.core.StringRedisTemplate;

class RedisLuaRateLimiterScriptTest {

    @Test
    void scriptUsesAtomicRedisIncrementWithExpiry() {
        assertThat(RedisLuaRateLimiter.FIXED_WINDOW_SCRIPT)
                .contains("INCR")
                .contains("PEXPIRE")
                .contains("return 0")
                .contains("return 1");
    }

    /**
     * Redis 不可用时退化为极小本地限额，而不是把登录/刷新等核心入口打成 503。
     *
     * <p>本地限额不跨实例，只保证故障窗口内不存在无限次尝试；总开关关闭时
     * 走同一档保护，两个分支都不得 fail-open。</p>
     */
    @Test
    void nullScriptResultFallsBackToMinimalLocalLimit() {
        StringRedisTemplate redisTemplate = mock(StringRedisTemplate.class);
        RateLimitProperties properties = new RateLimitProperties(true, 120, null, "omninest:rate-limit");
        RedisLuaRateLimiter limiter = new RedisLuaRateLimiter(redisTemplate, properties);
        String key = "login-" + UUID.randomUUID();

        assertThat(limiter.tryAcquire(key, 10, Duration.ofMinutes(1))).isTrue();
        assertThat(limiter.tryAcquire(key, 10, Duration.ofMinutes(1))).isTrue();
        assertThat(limiter.tryAcquire(key, 10, Duration.ofMinutes(1))).isTrue();
        assertThat(limiter.tryAcquire(key, 10, Duration.ofMinutes(1))).isFalse();
        // 一次性凭证校验成功后必须能归还占位，否则正确用户被自己锁在窗口内。
        limiter.release(key);
        assertThat(limiter.tryAcquire(key, 10, Duration.ofMinutes(1))).isTrue();
    }

    @Test
    void disabledSwitchKeepsMinimalLocalLimitInsteadOfFailingOpen() {
        StringRedisTemplate redisTemplate = mock(StringRedisTemplate.class);
        RateLimitProperties properties = new RateLimitProperties(false, 120, null, "omninest:rate-limit");
        RedisLuaRateLimiter limiter = new RedisLuaRateLimiter(redisTemplate, properties);
        String key = "share-" + UUID.randomUUID();

        assertThat(limiter.tryAcquire(key, 300, Duration.ofMinutes(1))).isTrue();
        assertThat(limiter.tryAcquire(key, 300, Duration.ofMinutes(1))).isTrue();
        assertThat(limiter.tryAcquire(key, 300, Duration.ofMinutes(1))).isTrue();
        assertThat(limiter.tryAcquire(key, 300, Duration.ofMinutes(1))).isFalse();
    }
}
