package com.omninest.worker.support;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.io.IOException;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * 死信前的本地重试语义。
 *
 * @author OmniNest
 */
class TransientRetryTest {

    @Test
    @DisplayName("瞬时失败重试后成功，不向上抛异常")
    void retriesTransientFailureAndSucceeds() throws Exception {
        AtomicInteger attempts = new AtomicInteger();

        String result = TransientRetry.call("测试动作", () -> {
            if (attempts.incrementAndGet() < 3) {
                throw new IOException("写锁冲突");
            }
            return "ok";
        });

        assertThat(result).isEqualTo("ok");
        assertThat(attempts).hasValue(3);
    }

    @Test
    @DisplayName("连续失败达到上限后抛出最后一次的原因")
    void rethrowsAfterAttemptsExhausted() {
        AtomicInteger attempts = new AtomicInteger();

        assertThatThrownBy(() -> TransientRetry.call("测试动作", () -> {
            attempts.incrementAndGet();
            throw new IOException("始终失败");
        }))
                .isInstanceOf(IOException.class)
                .hasMessage("始终失败");
        assertThat(attempts).hasValue(3);
    }
}
