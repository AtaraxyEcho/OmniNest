package com.omninest.common.cache;

import java.time.Duration;
import java.util.function.Predicate;
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
     * 从缓存读取数据，未命中时调用加载器；只有 {@code cacheable} 判定通过时才回填缓存。
     *
     * <p>上游瞬时故障经常以空结果或降级对象返回而不是抛异常。无条件回填会把一次网络抖动
     * 放大成整个 TTL 的数据缺失，因此这类加载器必须显式声明什么结果值得缓存。</p>
     *
     * @param key 缓存键
     * @param ttl 缓存有效期
     * @param loader 数据加载器
     * @param type 数据类型
     * @param cacheable 结果是否允许回填缓存
     * @param <T> 数据类型
     * @return 缓存值或加载结果
     */
    <T> T getOrLoadCachingWhen(
            String key,
            Duration ttl,
            Supplier<T> loader,
            Class<T> type,
            Predicate<T> cacheable);

    /**
     * 读取并删除缓存项，用于一次性令牌等不可重放的数据。
     *
     * @param key 缓存键
     * @return 原始缓存值；不存在时返回 null
     */
    String take(String key);

    /**
     * 按键模式批量失效缓存，用于清理同一归属下的一组动态键。
     *
     * @param pattern Redis 键匹配模式，调用方需保证前缀已按业务和归属命名
     */
    void evictPattern(String pattern);
}
