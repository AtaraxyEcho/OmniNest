package com.omninest.modules.music.service;

import com.omninest.common.config.BaseRuntimeConfigService;
import com.omninest.common.config.ConfigValueProvider;
import com.omninest.common.config.LegacyDeploymentConfigResolver;
import com.omninest.common.config.RuntimeConfigCache;
import com.omninest.modules.music.config.MusicProviderProperties;
import java.util.Arrays;
import java.util.List;
import java.util.Locale;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/**
 * 音乐模块运行时配置服务。
 * 从配置中心读取 MusicBrainz 元数据提供者相关的配置项。
 *
 * @author OmniNest
 */
@Slf4j
@Service
public class MusicRuntimeConfigService extends BaseRuntimeConfigService {

    public static final String MUSICBRAINZ_PROVIDER_ENABLED = "music.musicbrainz.enabled";
    public static final String MUSICBRAINZ_BASE_URL = "music.musicbrainz.url";
    public static final String MUSICBRAINZ_USER_AGENT = "music.musicbrainz.ua";
    public static final String MUSICBRAINZ_COVER_BASE_URL = "music.musicbrainz.cover-url";
    public static final String AUTO_IMPORT_ENABLED = "music.import.enabled";

    // 网易云
    public static final String NETEASE_ENABLED = "music.netease.enabled";
    public static final String NETEASE_BASE_URL = "music.netease.url";
    private static final String NETEASE_HOSTS = "music.netease.hosts";

    private static final String DEFAULT_MUSICBRAINZ_USER_AGENT = "OmniNest/0.1.0 (music@omninest.local)";
    private static final String DEFAULT_NETEASE_BASE_URL = "http://localhost:3001";
    private static final String ONLINE_ENABLED = "music.online.enabled";

    private final MusicProviderProperties deploymentProperties;
    private final LegacyDeploymentConfigResolver legacyDeploymentConfigResolver;

    /**
     * 创建音乐运行时配置服务。
     *
     * @param configValueProvider 配置值查询端口
     * @param runtimeConfigCache 运行时配置缓存端口
     */
    public MusicRuntimeConfigService(
            ConfigValueProvider configValueProvider,
            RuntimeConfigCache runtimeConfigCache,
            MusicProviderProperties deploymentProperties,
            LegacyDeploymentConfigResolver legacyDeploymentConfigResolver
    ) {
        super(configValueProvider, runtimeConfigCache);
        this.deploymentProperties = deploymentProperties;
        this.legacyDeploymentConfigResolver = legacyDeploymentConfigResolver;
    }

    public boolean autoImportEnabled() {
        return booleanWithLegacy(AUTO_IMPORT_ENABLED, "music.auto-import.enabled", true);
    }

    public boolean metadataProvidersEnabled() {
        return musicBrainzEnabled();
    }

    public boolean musicBrainzEnabled() {
        return booleanWithLegacy(MUSICBRAINZ_PROVIDER_ENABLED,
                "music.metadata-provider.musicbrainz.enabled", true);
    }

    public String musicBrainzBaseUrl() {
        return stringWithLegacy(MUSICBRAINZ_BASE_URL,
                "music.metadata-provider.musicbrainz.base-url", "https://musicbrainz.org/ws/2");
    }

    public String musicBrainzUserAgent() {
        return nonDefaultConfigValue(MUSICBRAINZ_USER_AGENT, DEFAULT_MUSICBRAINZ_USER_AGENT)
                .or(() -> nonDefaultConfigValue(
                        "music.metadata-provider.musicbrainz.user-agent",
                        DEFAULT_MUSICBRAINZ_USER_AGENT
                ))
                .orElseGet(() -> legacyDeploymentConfigResolver.stringValue(
                        "OMNINEST_MUSICBRAINZ_USER_AGENT",
                        MUSICBRAINZ_USER_AGENT,
                        deploymentProperties.getMusicBrainzUserAgent(),
                        DEFAULT_MUSICBRAINZ_USER_AGENT
                ));
    }

    public long musicBrainzRequestDelayMs() {
        return 1100L;
    }

    public String musicBrainzCoverBaseUrl() {
        return stringWithLegacy(MUSICBRAINZ_COVER_BASE_URL,
                "music.metadata-provider.musicbrainz.cover-base-url", "https://coverartarchive.org/release");
    }

    /** 在线音乐功能总开关。 */
    public boolean onlineEnabled() {
        return booleanWithLegacy(ONLINE_ENABLED, "music.platform.online.enabled", true);
    }

    /** 网易云音乐平台开关。 */
    public boolean neteaseEnabled() {
        return booleanWithLegacy(NETEASE_ENABLED, "music.platform.netease.enabled", true);
    }

    /** 网易云音乐 Docker 侧车服务地址。 */
    public String neteaseBaseUrl() {
        return nonDefaultConfigValue(NETEASE_BASE_URL, DEFAULT_NETEASE_BASE_URL)
                .or(() -> nonDefaultConfigValue(
                        "music.platform.netease.base-url",
                        DEFAULT_NETEASE_BASE_URL
                ))
                .orElseGet(() -> legacyDeploymentConfigResolver.stringValue(
                        "OMNINEST_NETEASE_API_BASE_URL",
                        NETEASE_BASE_URL,
                        deploymentProperties.getNeteaseBaseUrl(),
                        DEFAULT_NETEASE_BASE_URL
                ));
    }

    /** 网易云 API 请求延迟（毫秒），用于避免反爬。 */
    public long neteaseRequestDelayMs() {
        return 100L;
    }

    /**
     * 返回指定音乐平台明确配置的可信访问地址。
     *
     * @param sourcePlatform 音乐来源平台
     * @return 指定平台的 API 地址列表
     */
    public List<String> trustedPlatformUrls(String sourcePlatform) {
        if (!onlineEnabled()) {
            return List.of();
        }
        String normalizedPlatform = normalizePlatform(sourcePlatform);
        if ("netease".equals(normalizedPlatform) && neteaseEnabled()) {
            return List.of(neteaseBaseUrl());
        }
        return List.of();
    }

    /**
     * 返回指定平台允许兼容代理 Fake-IP 的官方播放域名后缀。
     *
     * @param sourcePlatform 音乐来源平台
     * @return 规范化后的域名后缀列表
     */
    public List<String> trustedPlaybackHostSuffixes(String sourcePlatform) {
        if (!onlineEnabled()) {
            return List.of();
        }
        String normalizedPlatform = normalizePlatform(sourcePlatform);
        String configuredValue;
        if ("netease".equals(normalizedPlatform) && neteaseEnabled()) {
            configuredValue = stringWithLegacy(NETEASE_HOSTS,
                    "music.platform.netease.playback-host-suffixes", "music.126.net,music.163.com");
        } else {
            return List.of();
        }
        return Arrays.stream(configuredValue.split(","))
                .map(String::trim)
                .map(value -> value.toLowerCase(Locale.ROOT))
                .map(this::removeLeadingDots)
                .filter(value -> !value.isBlank())
                .distinct()
                .toList();
    }

    private String normalizePlatform(String sourcePlatform) {
        return sourcePlatform == null ? "" : sourcePlatform.trim().toLowerCase(Locale.ROOT);
    }

    private String removeLeadingDots(String value) {
        String normalized = value;
        while (normalized.startsWith(".")) {
            normalized = normalized.substring(1);
        }
        return normalized;
    }

    @Override
    public boolean booleanConfig(String key, boolean defaultValue) {
        return cachedConfigValue(key)
                .map(value -> parseBoolean(value, defaultValue))
                .orElseGet(() -> {
                    log.debug("配置未找到，使用默认值: key={}, default={}", key, defaultValue);
                    return defaultValue;
                });
    }

    @Override
    public String stringConfig(String key, String defaultValue) {
        return cachedConfigValue(key)
                .map(value -> value == null ? defaultValue : value.trim())
                .filter(value -> !value.isBlank())
                .orElseGet(() -> {
                    log.debug("配置未找到，使用默认值: key={}, default={}", key, defaultValue);
                    return defaultValue;
                });
    }

    private boolean booleanWithLegacy(String key, String legacyKey, boolean defaultValue) {
        return cachedConfigValue(key)
                .or(() -> cachedConfigValue(legacyKey))
                .map(value -> parseBoolean(value, defaultValue))
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
