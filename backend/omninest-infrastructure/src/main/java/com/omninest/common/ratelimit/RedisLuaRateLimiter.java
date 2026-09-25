package com.omninest.common.ratelimit;

import java.time.Duration;
import java.util.List;
import lombok.RequiredArgsConstructor;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.script.DefaultRedisScript;
import org.springframework.stereotype.Service;

@Service
@RequiredArgsConstructor
public class RedisLuaRateLimiter implements RateLimitService {
    public static final String FIXED_WINDOW_SCRIPT = """
            local current = redis.call('INCR', KEYS[1])
            if tonumber(current) == 1 then
              redis.call('PEXPIRE', KEYS[1], ARGV[2])
            end
            if tonumber(current) > tonumber(ARGV[1]) then
              return 0
            end
            return 1
            """;

    private final StringRedisTemplate redisTemplate;
    private final RateLimitProperties properties;
    private final DefaultRedisScript<Long> script = new DefaultRedisScript<>(FIXED_WINDOW_SCRIPT, Long.class);

    @Override
    public boolean tryAcquire(String key, int limit, Duration window) {
        if (!properties.enabled()) {
            // 总开关关闭时高风险路径仍需保护：退化为极小本地限额，避免全局 fail-open。
            return LocalFallbackRateLimiter.tryAcquire(key, Math.min(limit, 3), window);
        }
        String redisKey = properties.keyPrefix() + ":" + key;
        Long allowed = RedisRateLimitExecutor.execute(
                "fixed-window",
                () -> redisTemplate.execute(
                        script,
                        List.of(redisKey),
                        Integer.toString(limit),
                        Long.toString(window.toMillis())
                )
        );
        return Long.valueOf(1L).equals(allowed);
    }
}
