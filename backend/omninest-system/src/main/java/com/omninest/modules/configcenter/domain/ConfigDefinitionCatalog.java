package com.omninest.modules.configcenter.domain;

import java.math.BigDecimal;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;

/**
 * 配置中心唯一可编辑目录。
 *
 * <p>目录只包含经过批准、适合由管理员动态调整的业务配置。未列入目录的部署边界、
 * 凭据托管和算法内部参数由 application 配置或业务代码提供稳定默认值。旧键保留在隐藏集合中，
 * 用于阻止旧客户端继续写入。
 */
public final class ConfigDefinitionCatalog {
    private static final List<String> BOOLEAN_VALUES = List.of("true", "false");
    private static final Map<String, ConfigDefinition> DEFINITIONS = buildDefinitions();
    private static final Set<String> HIDDEN_KEYS = Set.of(
            "media.metadata-providers.enabled",
            "media.metadata-provider.tmdb.enabled",
            "media.metadata-provider.tmdb.api-key",
            "media.metadata-provider.tmdb.access-token",
            "media.metadata-provider.tmdb.base-url",
            "media.metadata-provider.tmdb.language",
            "media.metadata-provider.tmdb.timeout-seconds",
            "media.metadata-provider.tmdb.search-queries-strategy",
            "media.metadata-provider.tmdb.max-results",
            "media.metadata-provider.tmdb.include-adult",
            "media.auto-import.enabled",
            "transcode.enabled",
            "reader.metadata-providers.enabled",
            "reader.metadata-provider.google-books.enabled",
            "reader.metadata-provider.google-books.base-url",
            "reader.metadata-provider.google-books.language",
            "reader.metadata-provider.google-books.max-results",
            "reader.metadata-provider.google-books.timeout-seconds",
            "reader.metadata-provider.google-books.api-key",
            "reader.metadata-provider.open-library.enabled",
            "reader.metadata-provider.open-library.base-url",
            "reader.metadata-provider.open-library.language",
            "reader.metadata-provider.open-library.timeout-seconds",
            "reader.metadata-provider.open-library.max-results",
            "reader.auto-import.enabled",
            "music.metadata-providers.enabled",
            "music.metadata-provider.musicbrainz.enabled",
            "music.metadata-provider.musicbrainz.base-url",
            "music.metadata-provider.musicbrainz.user-agent",
            "music.metadata-provider.musicbrainz.cover-base-url",
            "music.metadata-provider.musicbrainz.request-delay-ms",
            "music.auto-import.enabled",
            "music.platform.online.enabled",
            "music.platform.netease.enabled",
            "music.platform.netease.base-url",
            "music.platform.netease.request-delay-ms",
            "music.platform.netease.playback-host-suffixes",
            "music.platform.qq.enabled",
            "music.platform.qq.u-url",
            "music.platform.qq.c-url",
            "music.platform.qq.playback-host-suffixes",
            "photo.ai.endpoint",
            "photo.ai.timeout-seconds",
            "photo.backup.enabled",
            "photo.geo.rate-limit-per-second",
            "photo.geo.cache-enabled",
            "storage.quota.warning.percent",
            "storage.quota.default.gb",
            "shared_space.enabled",
            "shared_space.max_bytes",
            "upload.bandwidth.enabled",
            "upload.bandwidth.max-parts-per-second",
            "upload.bandwidth.burst-capacity",
            "rate-limit.default-limit",
            "security.clamav.enabled",
            "security.clamav.host",
            "security.clamav.port",
            "security.clamav.timeout-millis",
            "weather.qweather.project-id",
            "weather.qweather.credential-id",
            "weather.qweather.base-url",
            "weather.qweather.private-key",
            "file.local-media.enabled",
            "file.local-media.max-files-per-scan",
            "file.local-media.max-scan-depth"
    );

    private ConfigDefinitionCatalog() {
    }

    public static List<ConfigDefinition> definitions() {
        return List.copyOf(DEFINITIONS.values());
    }

    public static Optional<ConfigDefinition> find(String key) {
        return Optional.ofNullable(DEFINITIONS.get(key));
    }

    public static boolean isKnownHidden(String key) {
        return HIDDEN_KEYS.contains(key);
    }

    private static Map<String, ConfigDefinition> buildDefinitions() {
        Map<String, ConfigDefinition> values = new LinkedHashMap<>();

        // 系统与业务行为。
        add(values, bool("media.transcode.enabled", true, "media", ConfigSurface.GENERAL,
                "config.media.transcode", "是否启用媒体转码"));
        add(values, bool("media.import.enabled", true, "media", ConfigSurface.GENERAL,
                "config.media.autoImport", "是否启用媒体自动导入"));
        add(values, bool("reader.import.enabled", true, "reader", ConfigSurface.GENERAL,
                "config.reader.import", "是否启用阅读内容自动导入"));
        add(values, bool("photo.backup", true, "photo", ConfigSurface.GENERAL,
                "config.photo.backup", "是否启用照片自动备份"));
        add(values, number("photo.geo.rate", "1", "photo", ConfigSurface.GENERAL,
                "config.photo.geo.rate", "地理编码每秒请求上限", 1, 10));
        add(values, bool("photo.geo.offline", true, "photo", ConfigSurface.GENERAL,
                "config.photo.geo.offline", "是否启用 GeoNames 离线逆地理编码"));
        add(values, bool("photo.geo.nominatim", false, "photo", ConfigSurface.GENERAL,
                "config.photo.geo.nominatim", "离线未命中时是否回退 Nominatim 在线服务"));
        add(values, number("photo.geo.max-distance-km", "100", "photo", ConfigSurface.GENERAL,
                "config.photo.geo.maxDistance", "离线最近城市最大可信距离（公里，0 表示不限制）", 0, 2000));
        add(values, number("photo.geo.import.batch-size", "1000", "photo", ConfigSurface.GENERAL,
                "config.photo.geo.importBatchSize", "GeoNames 导入每批写入行数", 100, 10_000));
        add(values, bool("photo.geo.import.auto", true, "photo", ConfigSurface.GENERAL,
                "config.photo.geo.importAuto", "启动时无已发布数据集且文件齐全时自动触发 GeoNames 导入"));
        add(values, number("storage.quota.default", "10", "storage", ConfigSurface.GENERAL,
                "config.storage.defaultQuota", "新用户默认存储配额（GB，0 表示无限制）", 0, 1_048_576));
        add(values, number("storage.quota.warning", "80", "storage", ConfigSurface.GENERAL,
                "config.storage.warningPercent", "存储配额预警阈值百分比", 1, 100));
        add(values, bool("share.enabled", true, "storage", ConfigSurface.GENERAL,
                "config.storage.sharedSpace", "是否启用共享空间"));
        add(values, number("share.max-bytes", "322122547200", "storage", ConfigSurface.GENERAL,
                "config.storage.sharedSpaceLimit", "共享空间最大容量（字节，0 表示无限制）", 0, Long.MAX_VALUE));
        add(values, bool("upload.rate.enabled", true, "upload", ConfigSurface.GENERAL,
                "config.upload.rate", "是否启用上传签发限速"));
        add(values, number("security.rate-limit", "120", "security", ConfigSurface.GENERAL,
                "config.security.rateLimit", "默认接口限流上限", 1, 1_000_000));
        add(values, bool("clamav.enabled", true, "security", ConfigSurface.GENERAL,
                "config.security.clamav.enabled", "是否启用 ClamAV 文件安全扫描"));
        add(values, string("clamav.host", "localhost", "security", ConfigSurface.GENERAL,
                "config.security.clamav.host", "ClamAV 服务主机", false, 255));
        add(values, number("clamav.port", "3310", "security", ConfigSurface.GENERAL,
                "config.security.clamav.port", "ClamAV 服务端口", 1, 65_535));
        add(values, number("clamav.timeout-millis", "2000000", "security", ConfigSurface.GENERAL,
                "config.security.clamav.timeout", "单文件安全扫描时限（毫秒，活性护栏）", 1_000, 3_600_000));
        add(values, number("security.quarantine.retention-days", "7", "security", ConfigSurface.GENERAL,
                "config.security.quarantine.retentionDays", "隔离滞留对象保留天数", 1, 90));
        add(values, string("auth.two-factor.required-roles", "SUPER_ADMIN,ADMIN", "auth", ConfigSurface.GENERAL,
                "config.auth.twoFactorRequiredRoles", "强制开启两步验证的角色编码列表（逗号分隔，留空表示全员自愿）", false, 200));
        add(values, bool("weather.enabled", true, "weather", ConfigSurface.INTEGRATION,
                "config.weather.enabled", "是否启用天气服务"));

        // 外部服务与元数据提供者。
        add(values, bool("media.tmdb.enabled", true, "media", ConfigSurface.INTEGRATION,
                "config.integration.tmdb.enabled", "是否启用 TMDB"));
        add(values, sensitive("media.tmdb.key", "", "media", ConfigSurface.INTEGRATION,
                "config.integration.tmdb.apiKey", "TMDB v3 API Key", 1024));
        add(values, sensitive("media.tmdb.token", "", "media", ConfigSurface.INTEGRATION,
                "config.integration.tmdb.accessToken", "TMDB v4 Access Token", 2048));
        add(values, string("media.tmdb.url", "https://api.themoviedb.org/3", "media", ConfigSurface.INTEGRATION,
                "config.integration.tmdb.baseUrl", "TMDB API 基础地址", false, 512));
        add(values, string("media.tmdb.lang", "zh-CN", "media", ConfigSurface.INTEGRATION,
                "config.integration.tmdb.language", "TMDB 返回语言", false, 32));
        add(values, number("media.tmdb.timeout", "15", "media", ConfigSurface.INTEGRATION,
                "config.integration.tmdb.timeout", "TMDB 请求超时（秒）", 3, 120));
        add(values, enumString("media.tmdb.strategy", "NORMALIZED_AND_FALLBACKS", "media",
                ConfigSurface.INTEGRATION, "config.integration.tmdb.strategy", "TMDB 搜索策略",
                List.of("NORMALIZED_ONLY", "NORMALIZED_AND_FALLBACKS", "RAW_ONLY"), 64));
        add(values, number("media.tmdb.limit", "8", "media", ConfigSurface.INTEGRATION,
                "config.integration.tmdb.maxResults", "TMDB 单次搜索结果上限", 1, 20));
        add(values, bool("media.tmdb.adult", false, "media", ConfigSurface.INTEGRATION,
                "config.integration.tmdb.includeAdult", "TMDB 是否包含成人内容"));

        add(values, bool("reader.gbooks.enabled", false, "reader", ConfigSurface.INTEGRATION,
                "config.integration.googleBooks.enabled", "是否启用 Google Books"));
        add(values, string("reader.gbooks.url", "https://www.googleapis.com/books/v1", "reader",
                ConfigSurface.INTEGRATION, "config.integration.googleBooks.baseUrl", "Google Books API 地址", false, 512));
        add(values, string("reader.gbooks.lang", "zh-CN", "reader", ConfigSurface.INTEGRATION,
                "config.integration.googleBooks.language", "Google Books 返回语言", false, 32));
        add(values, number("reader.gbooks.limit", "5", "reader", ConfigSurface.INTEGRATION,
                "config.integration.googleBooks.maxResults", "Google Books 单次搜索结果上限", 1, 20));
        add(values, number("reader.gbooks.timeout", "40", "reader", ConfigSurface.INTEGRATION,
                "config.integration.googleBooks.timeout", "Google Books 请求超时（秒）", 3, 120));
        add(values, sensitive("reader.gbooks.key", "", "reader", ConfigSurface.INTEGRATION,
                "config.integration.googleBooks.apiKey", "Google Books API Key", 1024));
        add(values, bool("reader.openlib.enabled", false, "reader", ConfigSurface.INTEGRATION,
                "config.integration.openLibrary.enabled", "是否启用 Open Library"));
        add(values, string("reader.openlib.url", "https://openlibrary.org", "reader", ConfigSurface.INTEGRATION,
                "config.integration.openLibrary.baseUrl", "Open Library API 地址", false, 512));
        add(values, string("reader.openlib.lang", "zh", "reader", ConfigSurface.INTEGRATION,
                "config.integration.openLibrary.language", "Open Library 返回语言", false, 32));

        add(values, bool("music.musicbrainz.enabled", true, "music", ConfigSurface.INTEGRATION,
                "config.integration.musicbrainz.enabled", "是否启用 MusicBrainz"));
        add(values, bool("music.import.enabled", true, "music", ConfigSurface.GENERAL,
                "config.music.import", "是否启用音乐自动导入"));
        add(values, string("music.musicbrainz.url", "https://musicbrainz.org/ws/2", "music",
                ConfigSurface.INTEGRATION, "config.integration.musicbrainz.baseUrl", "MusicBrainz API 地址", false, 512));
        add(values, string("music.musicbrainz.ua", "OmniNest/0.1.0 (music@omninest.local)", "music",
                ConfigSurface.INTEGRATION, "config.integration.musicbrainz.userAgent", "MusicBrainz User-Agent", false, 512));
        add(values, string("music.musicbrainz.cover-url", "https://coverartarchive.org/release", "music",
                ConfigSurface.INTEGRATION, "config.integration.musicbrainz.coverBaseUrl", "MusicBrainz 封面地址", false, 512));
        add(values, bool("music.online.enabled", true, "music", ConfigSurface.INTEGRATION,
                "config.integration.music.online", "是否启用在线音乐"));
        add(values, bool("music.netease.enabled", true, "music", ConfigSurface.INTEGRATION,
                "config.integration.netease.enabled", "网易云音乐平台开关"));
        add(values, string("music.netease.url", "http://localhost:3001", "music", ConfigSurface.INTEGRATION,
                "config.integration.netease.baseUrl", "网易云音乐 API 地址", false, 512));
        add(values, string("music.netease.hosts", "music.126.net,music.163.com", "music", ConfigSurface.INTEGRATION,
                "config.integration.netease.hosts", "网易云音乐播放域名后缀", false, 512));
        add(values, bool("music.qq.enabled", true, "music", ConfigSurface.INTEGRATION,
                "config.integration.qq.enabled", "QQ 音乐平台开关"));
        add(values, string("music.qq.u-url", "https://u.y.qq.com/cgi-bin/musicu.fcg", "music",
                ConfigSurface.INTEGRATION, "config.integration.qq.uUrl", "QQ 音乐 U 接口地址", false, 512));
        add(values, string("music.qq.c-url", "https://c.y.qq.com", "music", ConfigSurface.INTEGRATION,
                "config.integration.qq.cUrl", "QQ 音乐 C 接口地址", false, 512));
        add(values, string("music.qq.hosts", "qqmusic.qq.com", "music", ConfigSurface.INTEGRATION,
                "config.integration.qq.hosts", "QQ 音乐播放域名后缀", false, 512));

        add(values, bool("photo.ai.enabled", true, "photo", ConfigSurface.INTEGRATION,
                "config.integration.photoAi.enabled", "是否启用图像分析"));
        add(values, string("photo.ai.url", "http://localhost:8090", "photo", ConfigSurface.INTEGRATION,
                "config.integration.photoAi.endpoint", "图像分析服务地址", false, 512));
        add(values, number("photo.ai.timeout", "30", "photo", ConfigSurface.INTEGRATION,
                "config.integration.photoAi.timeout", "图像分析请求超时（秒）", 3, 120));
        // 背景库。
        add(values, number("backdrop.max-image-bytes", "20971520", "backdrop", ConfigSurface.GENERAL,
                "config.backdrop.maxImageBytes", "背景图片单文件大小上限（字节）", 1024 * 1024, 128 * 1024 * 1024));
        add(values, number("backdrop.max-video-bytes", "67108864", "backdrop", ConfigSurface.GENERAL,
                "config.backdrop.maxVideoBytes", "背景视频单文件大小上限（字节）", 1024 * 1024, 128 * 1024 * 1024));
        add(values, number("backdrop.max-assets-per-user", "30", "backdrop", ConfigSurface.GENERAL,
                "config.backdrop.maxAssetsPerUser", "每用户背景素材数量上限", 1, 200));
        add(values, number("backdrop.upload.rate-per-hour", "20", "backdrop", ConfigSurface.GENERAL,
                "config.backdrop.uploadRatePerHour", "每用户每小时上传次数上限", 1, 1000));

        add(values, string("weather.qweather.project", "", "weather", ConfigSurface.INTEGRATION,
                "config.integration.qweather.projectId", "和风天气项目 ID", false, 255));
        add(values, string("weather.qweather.credential", "", "weather", ConfigSurface.INTEGRATION,
                "config.integration.qweather.credentialId", "和风天气凭据 ID", false, 255));
        add(values, string("weather.qweather.url", "https://devapi.qweather.com", "weather",
                ConfigSurface.INTEGRATION, "config.integration.qweather.baseUrl", "和风天气 API 地址", false, 512));
        add(values, sensitive("weather.qweather.key", "", "weather", ConfigSurface.INTEGRATION,
                "config.integration.qweather.privateKey", "和风天气 Ed25519 私钥", 8192));
        add(values, string("weather.location", "北京", "weather", ConfigSurface.INTEGRATION,
                "config.integration.qweather.location", "天气默认位置", false, 128));
        add(values, string("app.version.latest", "", "general", ConfigSurface.GENERAL,
                "config.appVersion.latest", "客户端最新版本号（留空表示已最新）", false, 64));
        add(values, string("app.version.release-notes-url", "", "general", ConfigSurface.GENERAL,
                "config.appVersion.releaseNotesUrl", "当前版本发布说明地址", false, 512));
        add(values, string("app.version.download-url", "", "general", ConfigSurface.GENERAL,
                "config.appVersion.downloadUrl", "安装包下载页地址", false, 512));
        return Map.copyOf(values);
    }

    private static ConfigDefinition bool(
            String key, boolean defaultValue, String category, ConfigSurface surface,
            String displayCode, String description
    ) {
        return new ConfigDefinition(
                key, Boolean.toString(defaultValue), ConfigValueType.BOOLEAN, category, RefreshScope.HOT,
                surface, displayCode, description, false, null, null, 5, BOOLEAN_VALUES
        );
    }

    private static ConfigDefinition number(
            String key, String defaultValue, String category, ConfigSurface surface,
            String displayCode, String description, long minValue, long maxValue
    ) {
        return new ConfigDefinition(
                key, defaultValue, ConfigValueType.NUMBER, category, RefreshScope.HOT, surface, displayCode,
                description, false, BigDecimal.valueOf(minValue), BigDecimal.valueOf(maxValue), 32, List.of()
        );
    }

    private static ConfigDefinition string(
            String key, String defaultValue, String category, ConfigSurface surface,
            String displayCode, String description, boolean sensitive, int maxLength
    ) {
        return new ConfigDefinition(
                key, defaultValue, ConfigValueType.STRING, category, RefreshScope.HOT, surface, displayCode,
                description, sensitive, null, null, maxLength, List.of()
        );
    }

    private static ConfigDefinition sensitive(
            String key, String defaultValue, String category, ConfigSurface surface,
            String displayCode, String description, int maxLength
    ) {
        return string(key, defaultValue, category, surface, displayCode, description, true, maxLength);
    }

    private static ConfigDefinition enumString(
            String key, String defaultValue, String category, ConfigSurface surface,
            String displayCode, String description, List<String> allowedValues, int maxLength
    ) {
        return new ConfigDefinition(
                key, defaultValue, ConfigValueType.STRING, category, RefreshScope.HOT, surface, displayCode,
                description, false, null, null, maxLength, allowedValues
        );
    }

    private static void add(Map<String, ConfigDefinition> values, ConfigDefinition definition) {
        if (values.put(definition.key(), definition) != null) {
            throw new IllegalStateException("配置目录存在重复键: " + definition.key());
        }
    }
}
