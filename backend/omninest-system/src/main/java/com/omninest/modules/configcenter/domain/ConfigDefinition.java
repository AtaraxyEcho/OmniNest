package com.omninest.modules.configcenter.domain;

import java.math.BigDecimal;
import java.net.URI;
import java.net.URISyntaxException;
import java.util.Arrays;
import java.util.List;
import java.util.Set;

/**
 * 受控运行时配置定义。
 *
 * @param key 配置键
 * @param defaultValue 默认值
 * @param valueType 值类型
 * @param category 业务分类
 * @param refreshScope 刷新范围
 * @param surface 管理界面归属
 * @param displayCode 前端本地化编码
 * @param description 运维说明
 * @param sensitive 是否为敏感值
 * @param minValue 最小数值
 * @param maxValue 最大数值
 * @param maxLength 字符串最大长度
 * @param allowedValues 允许的枚举值
 */
public record ConfigDefinition(
        String key,
        String defaultValue,
        ConfigValueType valueType,
        String category,
        RefreshScope refreshScope,
        ConfigSurface surface,
        String displayCode,
        String description,
        boolean sensitive,
        BigDecimal minValue,
        BigDecimal maxValue,
        int maxLength,
        List<String> allowedValues
) {
    private static final Set<String> URL_KEYS = Set.of(
            "media.tmdb.url",
            "reader.gbooks.url",
            "reader.openlib.url",
            "music.musicbrainz.url",
            "music.musicbrainz.cover-url",
            "music.netease.url",
            "photo.ai.url",
            "weather.qweather.url"
    );

    /**
     * 逗号分隔的运行目录相对路径清单配置：写入时就拒绝绝对路径与目录逃逸，
     * 避免直到清理任务执行才被发现配置根本无效。
     */
    private static final Set<String> RELATIVE_PATH_LIST_KEYS = Set.of("log-retention.scan-paths");

    public ConfigDefinition {
        allowedValues = List.copyOf(allowedValues);
    }

    /**
     * 标准化并校验外部提交值。
     *
     * @param rawValue 原始值
     * @return 标准化值
     */
    public String normalize(String rawValue) {
        if (rawValue == null) {
            throw new IllegalArgumentException("配置值不能为空");
        }
        if (rawValue.length() > maxLength) {
            throw new IllegalArgumentException("配置值长度超过限制");
        }
        return switch (valueType) {
            case BOOLEAN -> normalizeBoolean(rawValue);
            case NUMBER -> normalizeNumber(rawValue);
            case STRING, JSON -> normalizeString(rawValue);
        };
    }

    private String normalizeBoolean(String rawValue) {
        String normalized = rawValue.trim().toLowerCase();
        if (!"true".equals(normalized) && !"false".equals(normalized)) {
            throw new IllegalArgumentException("布尔配置只允许 true 或 false");
        }
        return normalized;
    }

    private String normalizeNumber(String rawValue) {
        BigDecimal value;
        try {
            value = new BigDecimal(rawValue.trim());
        } catch (NumberFormatException exception) {
            throw new IllegalArgumentException("数值配置格式不正确", exception);
        }
        if (minValue != null && value.compareTo(minValue) < 0) {
            throw new IllegalArgumentException("配置值低于允许范围");
        }
        if (maxValue != null && value.compareTo(maxValue) > 0) {
            throw new IllegalArgumentException("配置值高于允许范围");
        }
        if (value.stripTrailingZeros().scale() > 0) {
            throw new IllegalArgumentException("数值配置只允许整数");
        }
        return value.stripTrailingZeros().toPlainString();
    }

    /**
     * 判断该配置是否只能由超级管理员修改。
     *
     * @return 仅超级管理员可写时返回 true
     */
    public boolean superAdminOnly() {
        return "media.import.enabled".equals(key)
                || "log-retention.scan-paths".equals(key)
                || key.startsWith("media.tmdb.")
                || key.startsWith("music.")
                || key.startsWith("reader.gbooks.")
                || key.startsWith("reader.openlib.")
                || key.startsWith("photo.ai.")
                || key.startsWith("weather.qweather.")
                || key.startsWith("clamav.");
    }

    private String normalizeString(String rawValue) {
        if (!allowedValues.isEmpty() && allowedValues.stream().noneMatch(rawValue::equals)) {
            throw new IllegalArgumentException("配置值不在允许列表中");
        }
        if (RELATIVE_PATH_LIST_KEYS.contains(key)) {
            return normalizeRelativePathList(rawValue);
        }
        if (!URL_KEYS.contains(key)) {
            return rawValue;
        }
        return normalizeUrl(rawValue);
    }

    /**
     * 校验逗号分隔的相对路径清单：拒绝绝对路径、盘符、UNC 与 {@code ..} 逃逸。
     *
     * <p>保留清理会删除匹配到的文件，扫描根必须由部署确定而非由配置任意指定，
     * 因此这里只接受相对运行目录的路径段，执行侧再按日志基目录做一次边界校验。</p>
     */
    private String normalizeRelativePathList(String rawValue) {
        List<String> segments = Arrays.stream(rawValue.split(","))
                .map(String::trim)
                .filter(segment -> !segment.isEmpty())
                .toList();
        if (segments.isEmpty()) {
            throw new IllegalArgumentException("路径清单不能为空");
        }
        for (String segment : segments) {
            String normalized = segment.replace('\\', '/');
            if (normalized.startsWith("/") || normalized.contains("..")
                    || normalized.matches("^[A-Za-z]:.*") || normalized.indexOf('\0') >= 0) {
                throw new IllegalArgumentException("路径必须是运行目录下的相对路径：" + segment);
            }
        }
        return String.join(",", segments);
    }

    private String normalizeUrl(String rawValue) {
        String value = rawValue.trim();
        if (value.isBlank() || value.chars().anyMatch(Character::isISOControl)) {
            throw new IllegalArgumentException("服务地址不能为空或包含控制字符");
        }
        URI uri;
        try {
            uri = new URI(value);
        } catch (URISyntaxException exception) {
            throw new IllegalArgumentException("服务地址格式不正确", exception);
        }
        String scheme = uri.getScheme();
        if (scheme == null
                || !("http".equalsIgnoreCase(scheme) || "https".equalsIgnoreCase(scheme))
                || uri.getHost() == null
                || uri.getUserInfo() != null
                || uri.getQuery() != null
                || uri.getFragment() != null) {
            throw new IllegalArgumentException("服务地址必须是无凭据的 HTTP(S) 基础地址");
        }
        return value;
    }
}
