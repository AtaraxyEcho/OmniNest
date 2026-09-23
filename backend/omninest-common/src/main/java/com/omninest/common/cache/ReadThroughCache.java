package com.omninest.common.cache;

import java.time.Duration;
import java.util.function.Supplier;

/**
 * 提供缓存旁路读取和单键失效能力。
 *
 * @author OmniNest
 */
public interface ReadThroughCache {

    /**
     * 使指定缓存项失效。
     *
     * @param key 缓存键
     * @return 缓存项存在并被删除时返回 true
     */
    boolean invalidate(String key);

    /**
     * 从缓存读取数据，未命中时调用加载器并回填缓存。
     *
     * @param key 缓存键
     * @param ttl 缓存有效期
     * @param loader 数据加载器
     * @param type 数据类型
     * @param <T> 数据类型
     * @return 缓存值或加载结果
     */
    <T> T getOrLoad(String key, Duration ttl, Supplier<T> loader, Class<T> type);

    /**
     * 按键模式批量失效缓存，用于清理同一归属下的一组动态键。
     *
     * @param pattern Redis 键匹配模式，调用方需保证前缀已按业务和归属命名
     */
    void evictPattern(String pattern);
}
