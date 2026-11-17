package com.omninest.common.runtime;

import java.util.Locale;

/**
 * 定义 OmniNest 单镜像支持的运行角色。
 *
 * @author OmniNest
 */
public enum RuntimeRole {
    API,
    WORKER,
    SCHEDULER;

    /**
     * 将外部配置值转换为运行角色。
     *
     * @param value 外部配置值
     * @return 运行角色，空值默认返回 API
     * @throws IllegalArgumentException 配置值不受支持时抛出
     */
    public static RuntimeRole from(String value) {
        if (value == null || value.isBlank()) {
            return API;
        }
        try {
            return valueOf(value.trim().toUpperCase(Locale.ROOT));
        } catch (IllegalArgumentException exception) {
            throw new IllegalArgumentException("不支持的 OmniNest 运行角色: " + value, exception);
        }
    }

    /**
     * 返回 Spring 配置使用的小写角色值。
     *
     * @return 小写角色值
     */
    public String propertyValue() {
        return name().toLowerCase(Locale.ROOT);
    }
}
