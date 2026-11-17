package com.omninest.common.config;

import java.util.Optional;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.core.env.Environment;
import org.springframework.stereotype.Component;

/**
 * 在配置迁移观察期内读取仍存留于数据库的部署参数。
 *
 * <p>显式环境变量始终优先；旧值仅在环境变量未设置且不同于历史默认值时生效。告警只记录配置键和目标环境变量，
 * 不记录实际配置值。
 *
 * @author OmniNest
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class LegacyDeploymentConfigResolver {

    private final ConfigValueProvider configValueProvider;
    private final RuntimeConfigCache runtimeConfigCache;
    private final Environment environment;

    /**
     * 读取字符串部署属性，环境变量未显式设置时允许使用非默认旧值。
     */
    public String stringValue(
            String environmentName,
            String legacyKey,
            String deploymentValue,
            String legacyDefault
    ) {
        return legacyValue(environmentName, legacyKey, legacyDefault).orElse(deploymentValue);
    }

    /**
     * 读取布尔部署属性，环境变量未显式设置时允许使用非默认旧值。
     */
    public boolean booleanValue(
            String environmentName,
            String legacyKey,
            boolean deploymentValue,
            boolean legacyDefault
    ) {
        return legacyValue(environmentName, legacyKey, Boolean.toString(legacyDefault))
                .map(value -> "true".equalsIgnoreCase(value) || "1".equals(value))
                .orElse(deploymentValue);
    }

    /**
     * 读取有边界的整数部署属性，环境变量未显式设置时允许使用非默认旧值。
     */
    public int integerValue(
            String environmentName,
            String legacyKey,
            int deploymentValue,
            int legacyDefault,
            int minimum,
            int maximum
    ) {
        return legacyValue(environmentName, legacyKey, Integer.toString(legacyDefault))
                .flatMap(this::parseInteger)
                .filter(value -> value >= minimum && value <= maximum)
                .orElse(Math.clamp(deploymentValue, minimum, maximum));
    }

    private Optional<String> legacyValue(String environmentName, String legacyKey, String legacyDefault) {
        if (environment.getProperty(environmentName) != null) {
            return Optional.empty();
        }
        Optional<String> cachedValue = runtimeConfigCache.get(legacyKey);
        String value = cachedValue.or(() -> configValueProvider.findByKey(legacyKey)).orElse("").trim();
        if (value.isBlank() || value.equals(legacyDefault)) {
            return Optional.empty();
        }
        log.warn("检测到待迁移部署配置: key={}, targetEnvironment={}", legacyKey, environmentName);
        return Optional.of(value);
    }

    private Optional<Integer> parseInteger(String value) {
        try {
            return Optional.of(Integer.parseInt(value));
        } catch (NumberFormatException ignored) {
            return Optional.empty();
        }
    }
}
