package com.omninest.common.ratelimit;

import java.time.Duration;

/**
 * 提供固定时间窗口的请求限流能力。
 *
 * @author OmniNest
 */
public interface RateLimitService {

    /**
     * 尝试获取指定窗口内的请求许可。
     *
     * @param key 限流键
     * @param limit 窗口内允许的请求数量
     * @param window 时间窗口
     * @return 允许请求时返回 true
     */
    boolean tryAcquire(String key, int limit, Duration window);

    /**
     * 释放一次已获取的许可，用于「先占位、业务校验失败后归还」的一次性凭证场景。
     *
     * <p>窗口计数按单键维护，调用方必须只对专用的一次性键使用本方法，不得对
     * 账号/IP 等累计限流键调用，否则会重置他人的失败计数。</p>
     *
     * @param key 限流键
     */
    void release(String key);
}
