package com.omninest.common.ratelimit;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import org.junit.jupiter.api.Test;
import org.springframework.dao.QueryTimeoutException;
import org.springframework.data.redis.RedisConnectionFailureException;

class RedisRateLimitExecutorTest {

    @Test
    void connectionFailureIsConvertedToStableDependencyError() {
        assertDependencyUnavailable(() -> RedisRateLimitExecutor.execute(
                "fixed-window",
                () -> {
                    throw new RedisConnectionFailureException("connection failed");
                }
        ));
    }

    @Test
    void timeoutIsConvertedToStableDependencyError() {
        assertDependencyUnavailable(() -> RedisRateLimitExecutor.execute(
                "fixed-window",
                () -> {
                    throw new QueryTimeoutException("timed out");
                }
        ));
    }

    @Test
    void nullScriptResultIsConvertedToStableDependencyError() {
        assertDependencyUnavailable(() -> RedisRateLimitExecutor.execute("token-bucket", () -> null));
    }

    @Test
    void successfulResultIsReturnedUnchanged() {
        Long result = RedisRateLimitExecutor.execute("fixed-window", () -> 1L);

        assertThat(result).isEqualTo(1L);
    }

    private void assertDependencyUnavailable(Runnable operation) {
        assertThatThrownBy(operation::run)
                .isInstanceOfSatisfying(BusinessException.class, exception -> {
                    assertThat(exception.errorCode()).isEqualTo(ErrorCode.DEPENDENCY_UNAVAILABLE);
                    assertThat(exception.details())
                            .containsEntry("dependency", "redis")
                            .containsKey("capability");
                });
    }
}
