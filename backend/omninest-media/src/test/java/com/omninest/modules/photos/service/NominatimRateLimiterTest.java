package com.omninest.modules.photos.service;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Duration;
import org.junit.jupiter.api.Test;

/**
 * Nominatim 进程级速率限制状态测试。
 *
 * @author OmniNest
 */
class NominatimRateLimiterTest {

    @Test
    void consecutiveCallsShareTheSameRateLimitSchedule() {
        NominatimRateLimiter limiter = new NominatimRateLimiter();

        assertThat(limiter.tryAcquire(1, Duration.ZERO)).isTrue();
        assertThat(limiter.tryAcquire(1, Duration.ofMillis(10))).isFalse();
    }
}
