package com.omninest.common.config;

import java.util.Optional;

/**
 * 配置值提供者函数式接口。
 * 将配置读取抽象化，使 BaseRuntimeConfigService 不依赖具体的存储实现。
 *
 * @author OmniNest
 */
@FunctionalInterface
public interface ConfigValueProvider {

    /**
     * 根据配置键获取配置值。
     *
     * @param key 配置键
     * @return 配置值，不存在时返回 empty
     */
    Optional<String> findByKey(String key);
}
