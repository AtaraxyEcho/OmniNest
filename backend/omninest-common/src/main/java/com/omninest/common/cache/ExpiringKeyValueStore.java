package com.omninest.common.cache;

import java.time.Duration;

/**
 * 带过期时间的字符串键值端口。
 *
 * <p>给后台任务保存"下一轮从哪继续"这类游标：游标不是缓存命中语义（不需要回源、
 * 不需要单飞），也不是锁；直接注入 Redis 适配器会把业务模块绑到具体实现上。</p>
 *
 * @author OmniNest
 */
public interface ExpiringKeyValueStore {

    /**
     * 写入键值并设置过期时间。
     *
     * @param key 键
     * @param value 值
     * @param ttl 有效期
     */
    void set(String key, String value, Duration ttl);

    /**
     * 读取键值。
     *
     * @param key 键
     * @return 值；不存在时返回 {@code null}
     */
    String get(String key);

    /**
     * 删除键。
     *
     * @param key 键
     * @return 键存在并被删除时返回 true
     */
    boolean delete(String key);
}
