package com.omninest.modules.video.service;

import com.omninest.common.config.BaseRuntimeConfigService;
import com.omninest.common.config.ConfigValueProvider;
import com.omninest.common.config.RuntimeConfigCache;
import java.util.Locale;
import org.springframework.stereotype.Service;

/**
 * 媒体模块运行时配置服务。
 * 从配置中心读取视频元数据提供者相关的配置项。
 *
 * @author OmniNest
 */
@Service
public class MediaRuntimeConfigService extends BaseRuntimeConfigService {

    public static final String AUTO_IMPORT_ENABLED = "media.import.enabled";
    public static final String TMDB_PROVIDER_ENABLED = "media.tmdb.enabled";
    public static final String TMDB_API_KEY = "media.tmdb.key";
    public static final String TMDB_ACCESS_TOKEN = "media.tmdb.token";
    public static final String TMDB_LANGUAGE = "media.tmdb.lang";
    public static final String TMDB_INCLUDE_ADULT = "media.tmdb.adult";
    public static final String TMDB_BASE_URL = "media.tmdb.url";
    public static final String TMDB_TIMEOUT_SECONDS = "media.tmdb.timeout";
    public static final String TMDB_SEARCH_STRATEGY = "media.tmdb.strategy";
    public static final String TMDB_MAX_RESULTS = "media.tmdb.limit";
    public static final String TRANSCODE_ENABLED = "media.transcode.enabled";

    /**
     * 创建媒体运行时配置服务。
     *
     * @param configValueProvider 配置值查询端口
     * @param runtimeConfigCache 运行时配置缓存端口
     */
    public MediaRuntimeConfigService(
            ConfigValueProvider configValueProvider,
            RuntimeConfigCache runtimeConfigCache
    ) {
        super(configValueProvider, runtimeConfigCache);
    }

    public boolean autoImportEnabled() {
        return booleanWithLegacy(AUTO_IMPORT_ENABLED, "media.auto-import.enabled", true);
    }

    public boolean metadataProvidersEnabled() {
        return tmdbEnabled();
    }

    public boolean tmdbEnabled() {
        return booleanWithLegacy(TMDB_PROVIDER_ENABLED, "media.metadata-provider.tmdb.enabled", true);
    }

    public String tmdbBaseUrl() {
        return stringWithLegacy(TMDB_BASE_URL, "media.metadata-provider.tmdb.base-url",
                "https://api.themoviedb.org/3");
    }

    public String tmdbLanguage() {
        return stringWithLegacy(TMDB_LANGUAGE, "media.metadata-provider.tmdb.language", "zh-CN");
    }

    public boolean tmdbIncludeAdult() {
        return booleanWithLegacy(TMDB_INCLUDE_ADULT, "media.metadata-provider.tmdb.include-adult", false);
    }

    public int tmdbMaxResults() {
        return Math.clamp(intWithLegacy(TMDB_MAX_RESULTS, "media.metadata-provider.tmdb.max-results", 8), 1, 20);
    }

    public String tmdbSearchQueriesStrategy() {
        String value = stringWithLegacy(TMDB_SEARCH_STRATEGY,
                "media.metadata-provider.tmdb.search-queries-strategy", "NORMALIZED_AND_FALLBACKS")
                .trim().toUpperCase(Locale.ROOT);
        return switch (value) {
            case "NORMALIZED_ONLY", "NORMALIZED_AND_FALLBACKS", "RAW_ONLY" -> value;
            default -> "NORMALIZED_AND_FALLBACKS";
        };
    }

    public int tmdbTimeoutSeconds() {
        return Math.clamp(intWithLegacy(TMDB_TIMEOUT_SECONDS,
                "media.metadata-provider.tmdb.timeout-seconds", 15), 3, 120);
    }

    public boolean transcodeEnabled() {
        return booleanWithLegacy(TRANSCODE_ENABLED, "transcode.enabled", false);
    }

    /**
     * 读取 TMDB v3 API Key，并兼容迁移前的配置键。
     *
     * @return API Key，未配置时返回空字符串
     */
    public String tmdbApiKey() {
        return stringWithLegacy(TMDB_API_KEY, "media.metadata-provider.tmdb.api-key", "");
    }

    /**
     * 读取 TMDB v4 Bearer Token，并兼容迁移前的配置键。
     *
     * @return访问令牌，未配置时返回空字符串
     */
    public String tmdbAccessToken() {
        return stringWithLegacy(TMDB_ACCESS_TOKEN, "media.metadata-provider.tmdb.access-token", "");
    }

    private boolean booleanWithLegacy(String key, String legacyKey, boolean defaultValue) {
        return cachedConfigValue(key)
                .or(() -> cachedConfigValue(legacyKey))
                .map(value -> parseBoolean(value, defaultValue))
                .orElse(defaultValue);
    }

    private int intWithLegacy(String key, String legacyKey, int defaultValue) {
        return cachedConfigValue(key)
                .or(() -> cachedConfigValue(legacyKey))
                .map(value -> parseInt(value, defaultValue))
                .orElse(defaultValue);
    }

    private String stringWithLegacy(String key, String legacyKey, String defaultValue) {
        return cachedConfigValue(key)
                .or(() -> cachedConfigValue(legacyKey))
                .map(value -> value == null ? defaultValue : value.trim())
                .filter(value -> !value.isBlank())
                .orElse(defaultValue);
    }
}
