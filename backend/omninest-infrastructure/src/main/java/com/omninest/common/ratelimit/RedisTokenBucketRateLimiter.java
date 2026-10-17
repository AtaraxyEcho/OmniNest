package com.omninest.common.ratelimit;

import java.util.List;
import lombok.RequiredArgsConstructor;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.script.DefaultRedisScript;
import org.springframework.stereotype.Service;

/**
 * 基于 Redis Lua 脚本的令牌桶限速器。
 * <p>
 * 令牌桶以 HASH 存储：key=omninest:token-bucket:{key}, field=tokens, field=last_refill。
 * 每次请求消耗 1 个令牌，按 refillRatePerSecond 持续补充，不超过 bucketCapacity。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class RedisTokenBucketRateLimiter implements TokenBucketRateLimiter {

    /**
     * Lua 脚本：原子令牌桶操作。
     * <p>
     * KEYS[1] = 令牌桶 key
     * ARGV[1] = 桶容量
     * ARGV[2] = 每秒补充速率（乘以 1000 传入，避免浮点）
     * ARGV[3] = 当前时间戳毫秒
     * <p>
     * 返回：0 = 允许（无需等待）；正整数 = 拒绝且表示建议等待的毫秒数。
     * 放行与拒绝必须共用一个返回值域，否则 wait_ms 恰好为 1 的拒绝会被读成放行。
     */
    static final String TOKEN_BUCKET_SCRIPT = """
            local key = KEYS[1]
            local capacity = tonumber(ARGV[1])
            local refill_rate_x1000 = tonumber(ARGV[2])
            local now_ms = tonumber(ARGV[3])

            local tokens = tonumber(redis.call('HGET', key, 'tokens'))
            local last_refill = tonumber(redis.call('HGET', key, 'last_refill'))

            if tokens == nil then
              tokens = capacity
              last_refill = now_ms
            end

            -- 补充令牌
            local elapsed = now_ms - last_refill
            if elapsed > 0 and refill_rate_x1000 > 0 then
              local refill = (elapsed * refill_rate_x1000) / 1000000
              tokens = math.min(capacity, tokens + refill)
              last_refill = now_ms
            end

            -- 尝试消耗
            if tokens >= 1 then
              tokens = tokens - 1
              redis.call('HSET', key, 'tokens', tostring(tokens), 'last_refill', tostring(last_refill))
              redis.call('PEXPIRE', key, 60000)
              return 0
            else
              -- 计算需要等待的时间（毫秒），至少 1ms，保证与放行的 0 不冲突
              local wait_ms = 1000
              if refill_rate_x1000 > 0 then
                local deficit = 1 - tokens
                wait_ms = math.ceil((deficit * 1000000) / refill_rate_x1000)
              end
              if wait_ms < 1 then
                wait_ms = 1
              end
              redis.call('HSET', key, 'tokens', tostring(tokens), 'last_refill', tostring(last_refill))
              redis.call('PEXPIRE', key, 60000)
              return wait_ms
            end
            """;

    private final StringRedisTemplate redisTemplate;
    private final RateLimitProperties properties;
    private final DefaultRedisScript<Long> script = new DefaultRedisScript<>(TOKEN_BUCKET_SCRIPT, Long.class);

    /**
     * 尝试消耗一个令牌。
     *
     * @param key                 限速键（如 "upload:{userId}"）
     * @param bucketCapacity      桶容量（突发上限）
     * @param refillRatePerSecond 每秒补充令牌数
     * @return 结果
     */
    @Override
    public TokenBucketResult tryConsumeToken(
            String key,
            int bucketCapacity,
            double refillRatePerSecond
    ) {
        if (!properties.enabled()) {
            return new TokenBucketResult(true, 0);
        }
        if (bucketCapacity <= 0 || refillRatePerSecond <= 0) {
            return new TokenBucketResult(false, 1000);
        }
        String redisKey = properties.keyPrefix() + ":token-bucket:" + key;
        long refillRateX1000 = (long) (refillRatePerSecond * 1000);
        long nowMs = System.currentTimeMillis();

        Long result = RedisRateLimitExecutor.execute(
                "token-bucket",
                () -> redisTemplate.execute(
                        script,
                        List.of(redisKey),
                        Integer.toString(bucketCapacity),
                        Long.toString(refillRateX1000),
                        Long.toString(nowMs)
                )
        );

        return toTokenBucketResult(result);
    }

    /**
     * 把 Lua 返回值翻译为限流结论：0 放行，正数即拒绝并给出等待毫秒数。
     *
     * <p>放行与拒绝必须落在不重叠的返回值域，否则 wait_ms 为 1 的拒绝会被读成放行。</p>
     *
     * @param scriptResult 脚本返回的等待毫秒数，0 表示无需等待
     * @return 令牌消费结果
     */
    static TokenBucketResult toTokenBucketResult(long scriptResult) {
        if (scriptResult == 0L) {
            return new TokenBucketResult(true, 0);
        }
        return new TokenBucketResult(false, scriptResult);
    }
}
