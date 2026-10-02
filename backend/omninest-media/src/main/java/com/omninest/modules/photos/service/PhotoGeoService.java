package com.omninest.modules.photos.service;

import com.github.benmanes.caffeine.cache.Cache;
import com.github.benmanes.caffeine.cache.Caffeine;
import com.omninest.common.json.JsonSupport;
import com.omninest.common.ratelimit.RateLimitService;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.binder.cache.CaffeineCacheMetrics;
import jakarta.annotation.PostConstruct;
import java.math.BigDecimal;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import tools.jackson.databind.JsonNode;

/**
 * GPS 逆地理编码服务：离线 GeoNames 优先，Nominatim 仅作为可选兜底。
 *
 * <p>离线主路径完全本地：最近城市 + 双语名称格式化，无外部网络依赖；
 * 离线关闭、索引为空或坐标超距时，若 Nominatim 开关开启则回退在线服务。
 * 速率限制和缓存行为通过配置中心动态调整。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class PhotoGeoService {

    private static final String NOMINATIM_URL = "https://nominatim.openstreetmap.org/reverse";
    private static final Duration TIMEOUT = Duration.ofSeconds(10);
    private static final Duration RATE_LIMIT_WAIT = Duration.ofSeconds(2);
    private static final long MAX_CACHE_ENTRIES = 10_000;
    private static final Duration CACHE_TTL = Duration.ofHours(24);

    private static final String METRIC_OFFLINE_SUCCESS = "photo.geo.offline.success";
    private static final String METRIC_DISTANCE_REJECTED = "photo.geo.distance.rejected";
    private static final String METRIC_NOMINATIM_FALLBACK = "photo.geo.nominatim.fallback";
    private static final String METRIC_INVALID_COORDINATE = "photo.geo.invalid.coordinate";
    private static final String METRIC_NO_INDEX = "photo.geo.no.index";

    private final PhotosRuntimeConfigService configService;
    private final NominatimRateLimiter rateLimiter;
    private final RateLimitService distributedRateLimiter;
    private final MeterRegistry meterRegistry;
    private final GeoCityIndex geoCityIndex;

    private final Cache<String, Map<String, Object>> cache = Caffeine.newBuilder()
            .maximumSize(MAX_CACHE_ENTRIES)
            .expireAfterAccess(CACHE_TTL)
            .recordStats()
            .build();

    private final HttpClient httpClient = HttpClient.newBuilder()
            .connectTimeout(TIMEOUT)
            .build();

    /**
     * 注册地理编码缓存容量、命中和淘汰指标。
     */
    @PostConstruct
    public void registerCacheMetrics() {
        CaffeineCacheMetrics.monitor(meterRegistry, cache, "photo.geo.reverse");
    }

    /**
     * 逆地理编码：将经纬度转换为地名信息（使用当前在线索引快照）。
     *
     * @param latitude 纬度
     * @param longitude 经度
     * @return 地名信息 Map，无法解析时返回空 Map
     */
    public Map<String, Object> reverseGeocode(BigDecimal latitude, BigDecimal longitude) {
        return reverseGeocode(null, latitude, longitude);
    }

    /**
     * 逆地理编码：可绑定指定数据集快照（回填任务保证整个任务期间使用同一数据版本）。
     *
     * @param pinnedSnapshot 绑定快照，为 null 时使用当前在线快照
     * @param latitude 纬度
     * @param longitude 经度
     * @return 地名信息 Map，无法解析时返回空 Map
     */
    public Map<String, Object> reverseGeocode(
            GeoCitySnapshot pinnedSnapshot,
            BigDecimal latitude,
            BigDecimal longitude) {
        if (!isValidCoordinate(latitude, longitude)) {
            counter(METRIC_INVALID_COORDINATE).increment();
            return Map.of();
        }

        if (configService.isGeoOfflineEnabled()) {
            Optional<GeoCityMatch> nearest = nearest(latitude, longitude, pinnedSnapshot);
            if (nearest.isEmpty()) {
                counter(METRIC_NO_INDEX).increment();
            } else {
                int maxKm = configService.geoMaxDistanceKm();
                GeoCityMatch match = nearest.get();
                if (maxKm == 0 || match.distanceKm() <= maxKm) {
                    counter(METRIC_OFFLINE_SUCCESS).increment();
                    return GeoLocationFormatter.toGpsLocation(match);
                }
                // 距离超出可信范围（如海上坐标），不填充误导性地名。
                counter(METRIC_DISTANCE_REJECTED).increment();
            }
        }

        if (!configService.isNominatimEnabled()) {
            return Map.of();
        }
        counter(METRIC_NOMINATIM_FALLBACK).increment();
        return nominatimReverseGeocode(latitude, longitude);
    }

    /**
     * Nominatim 在线兜底：带缓存与双层速率限制。
     *
     * @param latitude 纬度
     * @param longitude 经度
     * @return 地名信息 Map，失败时返回空 Map
     */
    private Map<String, Object> nominatimReverseGeocode(BigDecimal latitude, BigDecimal longitude) {
        boolean cacheEnabled = configService.isGeoCacheEnabled();
        String cacheKey = String.format(Locale.ROOT, "%.2f,%.2f",
                latitude.doubleValue(), longitude.doubleValue());

        if (cacheEnabled) {
            Map<String, Object> cached = cache.getIfPresent(cacheKey);
            if (cached != null) {
                return cached;
            }
        }

        int rateLimit = Math.max(1, configService.geoRateLimitPerSecond());

        // Redis 分布式预检：多实例部署时防止超过全局速率
        if (!distributedRateLimiter.tryAcquire("nominatim:geo", rateLimit, Duration.ofSeconds(1))) {
            log.warn("Nominatim 分布式速率限制，跳过本次查询");
            return Map.of();
        }

        // 进程内间距控制：确保单实例内请求间隔不低于 1 秒
        if (!rateLimiter.tryAcquire(rateLimit, RATE_LIMIT_WAIT)) {
            log.warn("Nominatim 速率限制等待超时，跳过本次查询");
            return Map.of();
        }

        try {
            String url = NOMINATIM_URL
                    + "?lat=" + latitude.toPlainString()
                    + "&lon=" + longitude.toPlainString()
                    + "&format=json&accept-language=zh&zoom=14";
            HttpRequest request = HttpRequest.newBuilder(URI.create(url))
                    .timeout(TIMEOUT)
                    .header("User-Agent", "OmniNest/1.0 (photo-geocoder)")
                    .GET()
                    .build();
            HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());
            if (response.statusCode() != 200) {
                log.warn("Nominatim 请求失败: status={}", response.statusCode());
                return Map.of();
            }
            JsonNode json = JsonSupport.readTree(response.body());
            Map<String, Object> result = new HashMap<>();
            putIfNotBlank(result, "displayName", json.path("display_name").asText(null));
            JsonNode address = json.path("address");
            if (address.isObject()) {
                String city = firstNotBlank(
                        address.path("city").asText(null),
                        address.path("town").asText(null),
                        address.path("village").asText(null),
                        address.path("municipality").asText(null));
                String district = firstNotBlank(
                        address.path("city_district").asText(null),
                        address.path("district").asText(null),
                        address.path("county").asText(null),
                        address.path("suburb").asText(null));
                putIfNotBlank(result, "city", city);
                putIfNotBlank(result, "state", address.path("state").asText(null));
                putIfNotBlank(result, "district", district);
                putIfNotBlank(result, "country", address.path("country").asText(null));
                result.put("geocoder", "nominatim");
            }

            Map<String, Object> immutableResult = Map.copyOf(result);
            if (cacheEnabled) {
                cache.put(cacheKey, immutableResult);
            }
            return immutableResult;
        } catch (InterruptedException ex) {
            Thread.currentThread().interrupt();
            log.warn("逆地理编码被中断");
            return Map.of();
        } catch (Exception ex) {
            log.warn("逆地理编码失败: lat={}, lon={}, error={}", latitude, longitude, ex.getMessage());
            return Map.of();
        }
    }

    private Optional<GeoCityMatch> nearest(
            BigDecimal latitude,
            BigDecimal longitude,
            GeoCitySnapshot pinnedSnapshot) {
        GeoCitySnapshot target = pinnedSnapshot != null ? pinnedSnapshot : geoCityIndex.currentSnapshot();
        return GeoCityIndex.nearestInSnapshot(
                target,
                latitude.doubleValue(),
                longitude.doubleValue());
    }

    private static boolean isValidCoordinate(BigDecimal latitude, BigDecimal longitude) {
        if (latitude == null || longitude == null) {
            return false;
        }
        double lat = latitude.doubleValue();
        double lng = longitude.doubleValue();
        return !Double.isNaN(lat) && !Double.isNaN(lng)
                && !Double.isInfinite(lat) && !Double.isInfinite(lng)
                && lat >= -90.0 && lat <= 90.0
                && lng >= -180.0 && lng <= 180.0;
    }

    private io.micrometer.core.instrument.Counter counter(String name) {
        return meterRegistry.counter(name);
    }

    private void putIfNotBlank(Map<String, Object> target, String key, String value) {
        if (value != null && !value.isBlank()) {
            target.put(key, value);
        }
    }

    private String firstNotBlank(String... values) {
        for (String value : values) {
            if (value != null && !value.isBlank()) {
                return value;
            }
        }
        return null;
    }
}
