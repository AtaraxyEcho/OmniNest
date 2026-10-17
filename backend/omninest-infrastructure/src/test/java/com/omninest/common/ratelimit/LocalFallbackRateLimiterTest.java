package com.omninest.common.ratelimit;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Duration;
import java.util.UUID;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * 本地兜底限流器测试：窗口语义与键膨胀时的行为。
 *
 * @author OmniNest
 */
class LocalFallbackRateLimiterTest {

    @Test
    @DisplayName("窗口内按限额放行，超出后拒绝")
    void enforcesLimitWithinWindow() {
        String key = "local-window-" + UUID.randomUUID();

        assertThat(LocalFallbackRateLimiter.tryAcquire(key, 2, Duration.ofMinutes(5))).isTrue();
        assertThat(LocalFallbackRateLimiter.tryAcquire(key, 2, Duration.ofMinutes(5))).isTrue();
        assertThat(LocalFallbackRateLimiter.tryAcquire(key, 2, Duration.ofMinutes(5))).isFalse();
    }

    @Test
    @DisplayName("窗口过期后重新计数")
    void restartsCountAfterWindowElapsed() throws InterruptedException {
        String key = "local-expiry-" + UUID.randomUUID();

        assertThat(LocalFallbackRateLimiter.tryAcquire(key, 1, Duration.ofMillis(60))).isTrue();
        assertThat(LocalFallbackRateLimiter.tryAcquire(key, 1, Duration.ofMillis(60))).isFalse();
        Thread.sleep(120);
        assertThat(LocalFallbackRateLimiter.tryAcquire(key, 1, Duration.ofMillis(60))).isTrue();
    }

    @Test
    @DisplayName("新键涌入不得清空既有受限键的配额")
    void keepsLimitedKeyCountedWhileOtherKeysGrow() {
        String limitedKey = "local-overflow-" + UUID.randomUUID();
        LocalFallbackRateLimiter.tryAcquire(limitedKey, 1, Duration.ofMinutes(5));

        for (int index = 0; index < 2_000; index++) {
            LocalFallbackRateLimiter.tryAcquire("local-overflow-noise-" + index, 1, Duration.ofMinutes(5));
        }

        assertThat(LocalFallbackRateLimiter.tryAcquire(limitedKey, 1, Duration.ofMinutes(5))).isFalse();
    }

    @Test
    @DisplayName("参数非法时 fail-closed 拒绝")
    void rejectsInvalidArguments() {
        assertThat(LocalFallbackRateLimiter.tryAcquire(null, 5, Duration.ofMinutes(1))).isFalse();
        assertThat(LocalFallbackRateLimiter.tryAcquire("k", 0, Duration.ofMinutes(1))).isFalse();
        assertThat(LocalFallbackRateLimiter.tryAcquire("k", 5, null)).isFalse();
        assertThat(LocalFallbackRateLimiter.tryAcquire("k", 5, Duration.ZERO)).isFalse();
    }
}
