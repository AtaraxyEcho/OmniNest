package com.omninest.common.ratelimit;

import java.time.Duration;
import java.util.List;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.script.DefaultRedisScript;
import org.springframework.stereotype.Service;

@Slf4j
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
        Long allowed;
        try {
            allowed = RedisRateLimitExecutor.execute(
                    "fixed-window",
                    () -> redisTemplate.execute(
                            script,
                            List.of(redisKey),
                            Integer.toString(limit),
                            Long.toString(window.toMillis())
                    )
            );
        } catch (BusinessException exception) {
            if (exception.errorCode() != ErrorCode.DEPENDENCY_UNAVAILABLE) {
                throw exception;
            }
            // Redis 瞬断时不能让登录、刷新等核心入口整体不可用：退化为极小本地限额。
            // 本地限额不跨实例，只承担"Redis 故障期间不产生无限尝试"这一档风险。
            return LocalFallbackRateLimiter.tryAcquire(key, Math.min(limit, 3), window);
        }
        return Long.valueOf(1L).equals(allowed);
    }

    @Override
    public void release(String key) {
        // 无论当前走 Redis 还是本地兜底，都归还同一把一次性凭证的占位。
        LocalFallbackRateLimiter.release(key);
        if (!properties.enabled()) {
            return;
        }
        try {
            redisTemplate.delete(properties.keyPrefix() + ":" + key);
        } catch (RuntimeException exception) {
            // 归还失败只会把一次性凭证锁到窗口结束，不影响正确性；不得让释放异常
            // 覆盖调用方真正要返回的业务错误。
            log.warn("限流占位释放失败: key={}, errorType={}", key, exception.getClass().getSimpleName());
        }
    }
}
