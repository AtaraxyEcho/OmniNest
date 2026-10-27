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

    private static final int MAX_SHORT_WINDOW_KEYS = 10_000;
    private static final int MAX_LONG_WINDOW_KEYS = 5_000;

    /** 长窗口低频安全限流的分类阈值：该档不得与高频短窗口键共享淘汰池。 */
    private static final Duration LONG_WINDOW_THRESHOLD = Duration.ofMinutes(15);

    /**
     * 固定窗口计数器：条目在首次请求时创建，并按该次调用的窗口时长逐条过期。
     *
     * <p>键数量超过上限时按访问频率逐出个别条目，不得整表清空——清空会让正在受限的
     * 账号与 IP 立刻恢复满额，等于把键膨胀变成绕过限流的开关。</p>
     */
    private static final Cache<String, WindowCounter> SHORT_WINDOW_COUNTERS =
            newCounterCache(MAX_SHORT_WINDOW_KEYS);

    /**
     * 1 小时级安全限流（2FA 绑定/解绑、安装向导、索引重建等）单独一池：
     * 高频短窗口键的淘汰不得挤掉这些低频但高风险的计数器。
     */
    private static final Cache<String, WindowCounter> LONG_WINDOW_COUNTERS =
            newCounterCache(MAX_LONG_WINDOW_KEYS);

    private static Cache<String, WindowCounter> newCounterCache(long maximumSize) {
        return Caffeine.newBuilder()
                .maximumSize(maximumSize)
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
    }

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
        Cache<String, WindowCounter> counters =
                window.compareTo(LONG_WINDOW_THRESHOLD) >= 0 ? LONG_WINDOW_COUNTERS : SHORT_WINDOW_COUNTERS;
        WindowCounter counter = counters.get(key, ignored -> new WindowCounter(window.toNanos()));
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
