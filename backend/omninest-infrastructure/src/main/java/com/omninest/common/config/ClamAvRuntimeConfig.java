package com.omninest.common.config;

import java.time.Duration;
import java.util.Optional;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

/**
 * 从配置中心读取 ClamAV 文件扫描运行参数。
 *
 * @author OmniNest
 */
@Component
public class ClamAvRuntimeConfig {
    private static final String ENABLED = "clamav.enabled";
    private static final String HOST = "clamav.host";
    private static final String TIMEOUT_MILLIS = "clamav.timeout-millis";
    private static final int MINIMUM_TIMEOUT_MILLIS = 1_000;
    private static final int MAXIMUM_TIMEOUT_MILLIS = 3_600_000;

    private final ClamAvProperties properties;
    private final LegacyDeploymentConfigResolver legacyDeploymentConfigResolver;
    private final ConfigValueProvider configValueProvider;
    private final RuntimeConfigCache runtimeConfigCache;

    /**
     * 创建 ClamAV 运行时配置读取器。
     *
     * @param properties 环境配置默认值
     */
    @Autowired
    public ClamAvRuntimeConfig(
            ClamAvProperties properties,
            LegacyDeploymentConfigResolver legacyDeploymentConfigResolver,
            ConfigValueProvider configValueProvider,
            RuntimeConfigCache runtimeConfigCache
    ) {
        this.properties = properties;
        this.legacyDeploymentConfigResolver = legacyDeploymentConfigResolver;
        this.configValueProvider = configValueProvider;
        this.runtimeConfigCache = runtimeConfigCache;
    }

    /**
     * 保留无 Spring 测试构造器，便于验证部署默认值和兼容旧键。
     */
    public ClamAvRuntimeConfig(
            ClamAvProperties properties,
            LegacyDeploymentConfigResolver legacyDeploymentConfigResolver
    ) {
        this(properties, legacyDeploymentConfigResolver, null, null);
    }

    /**
     * 判断是否启用文件安全扫描。
     *
     * @return 是否启用扫描
     */
    public boolean isEnabled() {
        boolean deploymentEnabled = legacyDeploymentConfigResolver.booleanValue(
                "OMNINEST_CLAMAV_ENABLED",
                ENABLED,
                properties.isEnabled(),
                true
        );
        return configuredValue(ENABLED, "security.clamav.enabled")
                .map(value -> parseBoolean(value, deploymentEnabled))
                .orElse(deploymentEnabled);
    }

    /**
     * 获取 clamd 主机地址。
     *
     * @return clamd 主机地址
     */
    public String host() {
        String deploymentHost = legacyDeploymentConfigResolver.stringValue(
                "OMNINEST_CLAMAV_HOST",
                HOST,
                properties.getHost(),
                "localhost"
        );
        return configuredValue(HOST, "security.clamav.host").orElse(deploymentHost);
    }

    /**
     * 获取 clamd TCP 端口。
     *
     * @return clamd TCP 端口
     */
    public int port() {
        return configuredValue("clamav.port", "security.clamav.port")
                .map(value -> parseInt(value, -1))
                .filter(value -> value >= 1 && value <= 65_535)
                .orElse(Math.clamp(properties.getPort(), 1, 65_535));
    }

    /**
     * 获取单文件扫描时限。配置中心热值优先，越界或非法值回落部署默认值。
     *
     * @return 单文件扫描时限
     */
    public Duration timeout() {
        int deploymentTimeout = (int) Math.clamp(
                properties.getTimeout().toMillis(),
                MINIMUM_TIMEOUT_MILLIS,
                MAXIMUM_TIMEOUT_MILLIS
        );
        return configuredValue(TIMEOUT_MILLIS, "security.clamav.timeout-millis")
                .map(value -> parseInt(value, -1))
                .filter(value -> value >= MINIMUM_TIMEOUT_MILLIS && value <= MAXIMUM_TIMEOUT_MILLIS)
                .map(Duration::ofMillis)
                .orElse(Duration.ofMillis(deploymentTimeout));
    }

    private Optional<String> configuredValue(String key, String legacyKey) {
        if (configValueProvider == null) {
            return compatibilityValue(legacyKey);
        }
        Optional<String> cached = runtimeConfigCache == null
                ? Optional.empty()
                : runtimeConfigCache.get(key);
        return cached.or(() -> configValueProvider.findByKey(key))
                .or(() -> runtimeConfigCache == null
                        ? Optional.empty()
                        : runtimeConfigCache.get(legacyKey))
                .or(() -> configValueProvider.findByKey(legacyKey));
    }

    private Optional<String> compatibilityValue(String legacyKey) {
        return switch (legacyKey) {
            case "security.clamav.enabled" -> Optional.of(Boolean.toString(
                    legacyDeploymentConfigResolver.booleanValue(
                            "OMNINEST_CLAMAV_ENABLED",
                            legacyKey,
                            properties.isEnabled(),
                            true
                    )
            ));
            case "security.clamav.host" -> Optional.of(legacyDeploymentConfigResolver.stringValue(
                    "OMNINEST_CLAMAV_HOST",
                    legacyKey,
                    properties.getHost(),
                    "localhost"
            ));
            case "security.clamav.port" -> Optional.of(Integer.toString(
                    legacyDeploymentConfigResolver.integerValue(
                            "OMNINEST_CLAMAV_PORT",
                            legacyKey,
                            properties.getPort(),
                            3310,
                            1,
                            65_535
                    )
            ));
            case "security.clamav.timeout-millis" -> Optional.of(Integer.toString(
                    legacyDeploymentConfigResolver.integerValue(
                            "OMNINEST_CLAMAV_TIMEOUT_MILLIS",
                            legacyKey,
                            (int) Math.clamp(
                                    properties.getTimeout().toMillis(),
                                    MINIMUM_TIMEOUT_MILLIS,
                                    MAXIMUM_TIMEOUT_MILLIS
                            ),
                            10_000,
                            MINIMUM_TIMEOUT_MILLIS,
                            MAXIMUM_TIMEOUT_MILLIS
                    )
            ));
            default -> Optional.empty();
        };
    }

    private boolean parseBoolean(String value, boolean fallback) {
        if (value == null) {
            return fallback;
        }
        if ("true".equalsIgnoreCase(value.trim()) || "1".equals(value.trim())) {
            return true;
        }
        if ("false".equalsIgnoreCase(value.trim()) || "0".equals(value.trim())) {
            return false;
        }
        return fallback;
    }

    private int parseInt(String value, int fallback) {
        try {
            return Integer.parseInt(value.trim());
        } catch (RuntimeException exception) {
            return fallback;
        }
    }
}
