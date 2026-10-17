package com.omninest.common.ratelimit;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.data.redis.core.StringRedisTemplate;

/**
 * RedisTokenBucketRateLimiter 单元测试。
 * <p>
 * 由于 StringRedisTemplate.execute() 重载方法过多导致 Mockito stubbing 歧义，
 * Redis 交互部分通过集成测试覆盖，此处仅测试参数校验和脚本结构。
 *
 * @author OmniNest
 */
class RedisTokenBucketRateLimiterTest {

    private RateLimitProperties properties;
    private RedisTokenBucketRateLimiter limiter;

    @BeforeEach
    void setUp() {
        StringRedisTemplate redisTemplate = mock(StringRedisTemplate.class);
        properties = new RateLimitProperties(true, 120, null, "omninest:rate-limit");
        limiter = new RedisTokenBucketRateLimiter(redisTemplate, properties);
    }

    @Test
    @DisplayName("Lua 脚本包含令牌桶核心操作")
    void scriptContainsTokenBucketOperations() {
        assertThat(RedisTokenBucketRateLimiter.TOKEN_BUCKET_SCRIPT)
                .contains("HGET")
                .contains("HSET")
                .contains("PEXPIRE")
                .contains("math.min")
                .contains("math.ceil");
    }

    @Test
    @DisplayName("Lua 脚本处理 refill_rate 为零的除零保护")
    void scriptGuardsAgainstDivisionByZero() {
        assertThat(RedisTokenBucketRateLimiter.TOKEN_BUCKET_SCRIPT)
                .contains("refill_rate_x1000 > 0");
    }

    @Test
    @DisplayName("放行返回 0，拒绝返回的等待毫秒数下限钳到 1")
    void scriptKeepsAllowedAndRejectedReturnValueRangesDisjoint() {
        assertThat(RedisTokenBucketRateLimiter.TOKEN_BUCKET_SCRIPT)
                .contains("return 0")
                .contains("if wait_ms < 1 then");
    }

    @Test
    @DisplayName("脚本返回 1 是等待 1ms 的拒绝，不得读成放行")
    void classifiesOneMillisecondWaitAsRejection() {
        TokenBucketRateLimiter.TokenBucketResult rejected =
                RedisTokenBucketRateLimiter.toTokenBucketResult(1L);

        assertThat(rejected.allowed()).isFalse();
        assertThat(rejected.retryAfterMs()).isEqualTo(1);
        assertThat(RedisTokenBucketRateLimiter.toTokenBucketResult(0L).allowed()).isTrue();
    }

    @Test
    @DisplayName("禁用限速时始终允许")
    void allowsWhenDisabled() {
        RateLimitProperties disabled = new RateLimitProperties(false, 120, null, "omninest:rate-limit");
        StringRedisTemplate redisTemplate = mock(StringRedisTemplate.class);
        RedisTokenBucketRateLimiter disabledLimiter = new RedisTokenBucketRateLimiter(redisTemplate, disabled);

        TokenBucketRateLimiter.TokenBucketResult result = disabledLimiter.tryConsumeToken("test", 10, 5.0);

        assertThat(result.allowed()).isTrue();
        assertThat(result.retryAfterMs()).isEqualTo(0);
    }

    @Test
    @DisplayName("bucketCapacity <= 0 时拒绝")
    void rejectsWhenBucketCapacityIsZero() {
        TokenBucketRateLimiter.TokenBucketResult result = limiter.tryConsumeToken("test", 0, 5.0);

        assertThat(result.allowed()).isFalse();
        assertThat(result.retryAfterMs()).isEqualTo(1000);
    }

    @Test
    @DisplayName("bucketCapacity 为负数时拒绝")
    void rejectsWhenBucketCapacityIsNegative() {
        TokenBucketRateLimiter.TokenBucketResult result = limiter.tryConsumeToken("test", -1, 5.0);

        assertThat(result.allowed()).isFalse();
        assertThat(result.retryAfterMs()).isEqualTo(1000);
    }

    @Test
    @DisplayName("refillRatePerSecond 为零时拒绝")
    void rejectsWhenRefillRateIsZero() {
        TokenBucketRateLimiter.TokenBucketResult result = limiter.tryConsumeToken("test", 10, 0);

        assertThat(result.allowed()).isFalse();
        assertThat(result.retryAfterMs()).isEqualTo(1000);
    }

    @Test
    @DisplayName("refillRatePerSecond 为负数时拒绝")
    void rejectsWhenRefillRateIsNegative() {
        TokenBucketRateLimiter.TokenBucketResult result = limiter.tryConsumeToken("test", 10, -1.0);

        assertThat(result.allowed()).isFalse();
        assertThat(result.retryAfterMs()).isEqualTo(1000);
    }

    @Test
    @DisplayName("TokenBucketResult record 正确存储字段")
    void tokenBucketResultFields() {
        TokenBucketRateLimiter.TokenBucketResult allowed = new TokenBucketRateLimiter.TokenBucketResult(true, 0);
        assertThat(allowed.allowed()).isTrue();
        assertThat(allowed.retryAfterMs()).isEqualTo(0);

        TokenBucketRateLimiter.TokenBucketResult denied = new TokenBucketRateLimiter.TokenBucketResult(false, 500);
        assertThat(denied.allowed()).isFalse();
        assertThat(denied.retryAfterMs()).isEqualTo(500);
    }

    @Test
    @DisplayName("Redis 实现遵循令牌桶限流契约")
    void implementsTokenBucketContract() {
        assertThat(limiter).isInstanceOf(TokenBucketRateLimiter.class);
    }

    @Test
    @DisplayName("Redis 脚本返回空结果时按依赖不可用拒绝")
    void rejectsNullScriptResultAsDependencyUnavailable() {
        assertThatThrownBy(() -> limiter.tryConsumeToken("test", 10, 5.0))
                .isInstanceOfSatisfying(BusinessException.class, exception ->
                        assertThat(exception.errorCode()).isEqualTo(ErrorCode.DEPENDENCY_UNAVAILABLE));
    }
}
