package com.omninest.common.ratelimit;

import com.github.benmanes.caffeine.cache.Cache;
import com.github.benmanes.caffeine.cache.Caffeine;
import com.github.benmanes.caffeine.cache.Expiry;
import java.time.Duration;
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

    /**
     * 固定窗口计数器：条目在首次请求时创建，并按该次调用的窗口时长逐条过期。
     *
     * <p>键数量超过上限时按访问频率逐出个别条目，不得整表清空——清空会让正在受限的
     * 账号与 IP 立刻恢复满额，等于把键膨胀变成绕过限流的开关。</p>
     */
    private static final Cache<String, WindowCounter> COUNTERS = Caffeine.newBuilder()
            .maximumSize(MAX_TRACKED_KEYS)
            .expireAfter(new Expiry<String, WindowCounter>() {
                @Override
                public long expireAfterCreate(String key, WindowCounter value, long currentTime) {
                    return value.windowNanos;
                }

                @Override
                public long expireAfterUpdate(
                        String key, WindowCounter value, long currentTime, long currentDuration) {
                    return currentDuration;
                }

                @Override
                public long expireAfterRead(
                        String key, WindowCounter value, long currentTime, long currentDuration) {
                    return currentDuration;
                }
            })
            .build();

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
        WindowCounter counter = COUNTERS.get(key, ignored -> new WindowCounter(window.toNanos()));
        return counter.count.incrementAndGet() <= limit;
    }

    private static final class WindowCounter {
        private final long windowNanos;
        private final AtomicInteger count = new AtomicInteger();

        private WindowCounter(long windowNanos) {
            this.windowNanos = windowNanos;
        }
    }
}
