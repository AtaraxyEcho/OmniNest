package com.omninest.common.ratelimit;

/**
 * 提供令牌桶速率限制能力。
 *
 * @author OmniNest
 */
public interface TokenBucketRateLimiter {

    /**
     * 尝试从指定令牌桶消耗一个令牌。
     *
     * @param key 限流键
     * @param bucketCapacity 桶容量
     * @param refillRatePerSecond 每秒补充令牌数
     * @return 令牌消费结果
     */
    TokenBucketResult tryConsumeToken(
            String key,
            int bucketCapacity,
            double refillRatePerSecond
    );

    /**
     * 描述令牌消费结果和建议重试时间。
     *
     * @param allowed 是否允许本次操作
     * @param retryAfterMs 建议重试等待毫秒数
     * @author OmniNest
     */
    record TokenBucketResult(boolean allowed, long retryAfterMs) {
    }
}
