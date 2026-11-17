package com.omninest.common.config;

import java.util.Locale;
import java.util.Optional;
import lombok.RequiredArgsConstructor;

/**
 * 封装运行时配置的缓存读取、数据源回退和类型解析逻辑。
 *
 * @author OmniNest
 */
@RequiredArgsConstructor
public abstract class BaseRuntimeConfigService {

    protected final ConfigValueProvider configValueProvider;
    protected final RuntimeConfigCache runtimeConfigCache;

    /**
     * 读取配置值，并在缓存未命中时回退到配置数据源。
     *
     * @param key 配置键
     * @return 配置值
     */
    protected Optional<String> cachedConfigValue(String key) {
        Optional<String> cached = runtimeConfigCache.get(key);
        if (cached.isPresent()) {
            return cached;
        }
        Optional<String> storedValue = configValueProvider.findByKey(key);
        storedValue.ifPresent(value -> runtimeConfigCache.put(key, value));
        return storedValue;
    }

    /**
     * 读取已被管理员明确改写的配置值。配置中心仍保存默认行时，允许部署属性提供兼容默认值。
     *
     * @param key 配置键
     * @param defaultValue 目录默认值
     * @return 非空且不同于目录默认值的配置
     */
    protected Optional<String> nonDefaultConfigValue(String key, String defaultValue) {
        return cachedConfigValue(key)
                .map(value -> value == null ? "" : value.trim())
                .filter(value -> !value.isBlank() && !value.equals(defaultValue));
    }

    /**
     * 读取布尔类型配置。
     *
     * @param key 配置键
     * @param defaultValue 默认值
     * @return 配置值，解析失败时返回默认值
     */
    public boolean booleanConfig(String key, boolean defaultValue) {
        return cachedConfigValue(key)
                .map(value -> parseBoolean(value, defaultValue))
                .orElse(defaultValue);
    }

    /**
     * 读取字符串类型配置。
     *
     * @param key 配置键
     * @param defaultValue 默认值
     * @return 配置值，不存在或为空时返回默认值
     */
    public String stringConfig(String key, String defaultValue) {
        return cachedConfigValue(key)
                .map(value -> value == null ? defaultValue : value.trim())
                .filter(value -> !value.isBlank())
                .orElse(defaultValue);
    }

    /**
     * 读取整数类型配置。
     *
     * @param key 配置键
     * @param defaultValue 默认值
     * @return 配置值，解析失败时返回默认值
     */
    public int intConfig(String key, int defaultValue) {
        return cachedConfigValue(key)
                .map(value -> parseInt(value, defaultValue))
                .orElse(defaultValue);
    }

    /**
     * 读取长整数类型配置。字节大小等可超过 int 范围的配置必须用它，
     * 否则 {@code Integer.parseInt} 失败会被静默回落到默认值。
     *
     * @param key 配置键
     * @param defaultValue 默认值
     * @return 配置值，解析失败时返回默认值
     */
    public long longConfig(String key, long defaultValue) {
        return cachedConfigValue(key)
                .map(value -> parseLong(value, defaultValue))
                .orElse(defaultValue);
    }

    /**
     * 解析布尔配置值。
     *
     * @param value 待解析的配置值
     * @param defaultValue 默认值
     * @return 解析后的配置值
     */
    protected boolean parseBoolean(String value, boolean defaultValue) {
        if (value == null || value.isBlank()) {
            return defaultValue;
        }
        String normalized = value.trim().toLowerCase(Locale.ROOT);
        if ("true".equals(normalized) || "1".equals(normalized) || "yes".equals(normalized)) {
            return true;
        }
        if ("false".equals(normalized) || "0".equals(normalized) || "no".equals(normalized)) {
            return false;
        }
        return defaultValue;
    }

    /**
     * 解析整数配置值。
     *
     * @param value 待解析的配置值
     * @param defaultValue 默认值
     * @return 解析后的配置值
     */
    protected int parseInt(String value, int defaultValue) {
        if (value == null || value.isBlank()) {
            return defaultValue;
        }
        try {
            return Integer.parseInt(value.trim());
        } catch (NumberFormatException exception) {
            return defaultValue;
        }
    }

    /**
     * 解析长整数配置值。
     *
     * @param value 待解析的配置值
     * @param defaultValue 默认值
     * @return 解析后的配置值
     */
    protected long parseLong(String value, long defaultValue) {
        if (value == null || value.isBlank()) {
            return defaultValue;
        }
        try {
            return Long.parseLong(value.trim());
        } catch (NumberFormatException exception) {
            return defaultValue;
        }
    }
}
