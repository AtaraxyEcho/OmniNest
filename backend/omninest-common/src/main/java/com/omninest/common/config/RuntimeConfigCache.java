package com.omninest.common.config;

import java.util.Optional;

/**
 * 定义运行时配置缓存的读取、写入和失效能力。
 *
 * @author OmniNest
 */
public interface RuntimeConfigCache {

    /**
     * 读取配置缓存。
     *
     * @param key 配置键
     * @return 已缓存的配置值
     */
    Optional<String> get(String key);

    /**
     * 写入配置缓存。
     *
     * @param key 配置键
     * @param value 配置值
     */
    void put(String key, String value);

    /**
     * 清除指定配置项缓存。
     *
     * @param key 配置键
     */
    void evict(String key);

    /**
     * 清除全部运行时配置缓存。
     */
    void evictAll();
}
