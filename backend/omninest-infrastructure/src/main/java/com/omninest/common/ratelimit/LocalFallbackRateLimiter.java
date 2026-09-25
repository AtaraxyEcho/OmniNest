package com.omninest.common.ratelimit;

import java.time.Duration;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentMap;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * Redis 不可用或总开关关闭时的极小本地限流兜底。
 *
 * <p>仅用于高风险路径的 fail-closed 退化，不做持久化、不跨实例。</p>
 *
 * @author OmniNest
 */
public final class LocalFallbackRateLimiter {

    private static final int MAX_TRACKED_KEYS = 10_000;

    private static final ConcurrentMap<String, WindowCounter> COUNTERS = new ConcurrentHashMap<>();

    private LocalFallbackRateLimiter() {
    }

    /**
     * 在本地内存窗口内尝试占用一次配额。
     *
     * @param key 限流键
     * @param limit 窗口内允许次数
     * @param window 窗口时长
     * @return 是否允许本次请求
     */
    public static boolean tryAcquire(String key, int limit, Duration window) {
        if (key == null || limit <= 0 || window == null || window.isZero() || window.isNegative()) {
            return false;
        }
        if (COUNTERS.size() > MAX_TRACKED_KEYS) {
            COUNTERS.clear();
        }
        long now = System.nanoTime();
        long windowNanos = window.toNanos();
        WindowCounter counter = COUNTERS.compute(key, (k, existing) -> {
            if (existing == null || now - existing.startNanos > windowNanos) {
                return new WindowCounter(now);
            }
            return existing;
        });
        return counter.count.incrementAndGet() <= limit;
    }

    private static final class WindowCounter {
        private final long startNanos;
        private final AtomicInteger count = new AtomicInteger();

        private WindowCounter(long startNanos) {
            this.startNanos = startNanos;
        }
    }
}
