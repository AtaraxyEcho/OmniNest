package com.omninest.modules.weather.service;

import com.alibaba.fastjson2.JSON;
import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import com.nimbusds.jose.JWSAlgorithm;
import com.nimbusds.jose.JWSHeader;
import com.nimbusds.jose.crypto.Ed25519Signer;
import com.nimbusds.jose.jwk.Curve;
import com.nimbusds.jose.jwk.OctetKeyPair;
import com.nimbusds.jose.util.Base64URL;
import com.nimbusds.jwt.JWTClaimsSet;
import com.nimbusds.jwt.SignedJWT;
import com.omninest.common.config.ConfigRefreshEvent;
import com.omninest.common.config.ConfigValueProvider;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.weather.dto.WeatherDto;
import com.omninest.modules.weather.service.WeatherCacheStore.ResolvedWeatherLocation;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.net.URI;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.security.KeyFactory;
import java.security.PrivateKey;
import java.security.spec.PKCS8EncodedKeySpec;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Base64;
import java.util.Date;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.regex.Pattern;
import java.util.zip.GZIPInputStream;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.event.EventListener;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

/**
 * 天气服务
 *
 * 使用和风天气 API，JWT (Ed25519) 认证。
 * 缓存策略：JWT 55min，城市解析 24h，天气数据 10min。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class WeatherService {

    private static final Duration CONFIG_CACHE_TTL = Duration.ofMinutes(5);
    private static final Pattern COORD_PATTERN = Pattern.compile("^-?\\d{1,3}\\.\\d+,\\s*-?\\d{1,3}\\.\\d+$");
    private static final List<String> CONFIG_KEYS = List.of(
            "weather.enabled",
            "weather.qweather.url",
            "weather.location",
            "weather.qweather.project",
            "weather.qweather.credential",
            "weather.qweather.key"
    );

    private final ConfigValueProvider configValueProvider;
    private final WeatherCacheStore weatherCacheStore;
    private final RestTemplate restTemplate = createRestTemplate();

    /** 天气 API 专用线程池（虚拟线程，无需手动 shutdown） */
    private final ExecutorService weatherExecutor = Executors.newVirtualThreadPerTaskExecutor();

    /** JWT 生成锁 */
    private final Object jwtLock = new Object();

    /** 天气数据 singleflight：防止同一位置的并发请求穿透缓存 */
    private final ConcurrentHashMap<String, CompletableFuture<WeatherDto>> inflightRequests =
            new ConcurrentHashMap<>();

    /** 配置缓存 */
    private volatile Map<String, String> configCache;
    private volatile Instant configCacheExpiry = Instant.MIN;

    /**
     * 配置中心更新后立即失效本地天气配置快照，避免热更新被五分钟缓存延迟覆盖。
     *
     * @param event 配置刷新事件
     */
    @EventListener
    public void onConfigRefresh(ConfigRefreshEvent event) {
        if (event == null || event.key() == null || CONFIG_KEYS.contains(event.key())) {
            synchronized (this) {
                configCache = null;
                configCacheExpiry = Instant.MIN;
            }
        }
    }

    /**
     * 获取实时天气（聚合实时天气 + 空气质量 + 预报）
     *
     * 外部 API 业务失败（城市不存在、403 等）返回空数据做优雅降级。
     * 配置错误等关键问题抛出 BusinessException。
     */
    public WeatherDto getRealtimeWeather(String location) {
        return getRealtimeWeather(location, null);
    }

    /**
     * 获取实时天气。
     *
     * @param location API 查询位置（GPS 经纬度或城市名）
     * @param displayName 展示用地区名；location 为 GPS 时用于回填用户偏好城市
     */
    public WeatherDto getRealtimeWeather(String location, String displayName) {
        final Map<String, String> config = loadConfig();

        if (!"true".equalsIgnoreCase(config.get("weather.enabled"))) {
            return WeatherDto.empty();
        }

        String baseUrl = config.get("weather.qweather.url");
        String rawLocation = (location != null && !location.isBlank()) ? location.trim()
                : config.get("weather.location");
        final String effectiveDisplayName = resolveDisplayName(rawLocation, displayName, config);

        // 解析位置
        ResolvedWeatherLocation resolved = resolveLocation(rawLocation, config);
        if (resolved == null) {
            // 用户指定位置解析失败，尝试配置中心默认值
            String fallbackLocation = config.get("weather.location");
            if (fallbackLocation != null && !fallbackLocation.isBlank()
                    && !fallbackLocation.equals(rawLocation)) {
                resolved = resolveLocation(fallbackLocation, config);
            }
            if (resolved == null) {
                return WeatherDto.empty();
            }
        }

        // 检查天气数据缓存
        final ResolvedWeatherLocation finalResolved = resolved;
        final String finalBaseUrl = baseUrl;
        final String requestKey = finalResolved.latLon();
        WeatherDto cachedWeather = weatherCacheStore.findWeather(finalResolved.latLon()).orElse(null);
        if (cachedWeather != null) {
            return withLocationName(cachedWeather, effectiveDisplayName);
        }

        // singleflight：同一位置的并发请求复用同一个 Future，防止缓存击穿
        CompletableFuture<WeatherDto> existing = inflightRequests.get(requestKey);
        if (existing != null && !existing.isDone()) {
            try {
                return existing.get(6, TimeUnit.SECONDS);
            } catch (Exception e) {
                log.debug("等待 in-flight 天气请求超时，自行发起请求", e);
            }
        }

        CompletableFuture<WeatherDto> future = CompletableFuture.supplyAsync(() -> {
            try {
                // 预生成 JWT，并行请求外部 API
                String jwt = generateJwt(config);
                CompletableFuture<JSONObject> weatherNowFuture = CompletableFuture.supplyAsync(
                        () -> fetchApi(finalBaseUrl, "/v7/weather/now", finalResolved.weatherLocation(), jwt),
                        weatherExecutor
                );
                CompletableFuture<JSONObject> airNowFuture = CompletableFuture.supplyAsync(
                        () -> fetchAirQuality(finalBaseUrl, finalResolved.latLon(), jwt), weatherExecutor);
                CompletableFuture<JSONObject> weather7dFuture = CompletableFuture.supplyAsync(
                        () -> fetchApi(finalBaseUrl, "/v7/weather/7d", finalResolved.weatherLocation(), jwt),
                        weatherExecutor
                );
                CompletableFuture<JSONObject> weather24hFuture = CompletableFuture.supplyAsync(
                        () -> fetchApi(finalBaseUrl, "/v7/weather/24h", finalResolved.weatherLocation(), jwt),
                        weatherExecutor
                );

                JSONObject weatherNow = getOrNull(weatherNowFuture);
                JSONObject airNow = getOrNull(airNowFuture);
                JSONObject weather7d = getOrNull(weather7dFuture);
                JSONObject weather24h = getOrNull(weather24hFuture);

                if (weatherNow == null) {
                    return WeatherDto.empty();
                }

                WeatherDto result = aggregateWeather(
                        weatherNow, airNow, weather7d, weather24h,
                        finalResolved.locationName() != null && !finalResolved.locationName().isBlank()
                                ? finalResolved.locationName()
                                : effectiveDisplayName);
                weatherCacheStore.saveWeather(finalResolved.latLon(), result);
                return result;
            } catch (Exception e) {
                log.error("获取天气数据失败", e);
                return WeatherDto.empty();
            }
        }, weatherExecutor);

        // putIfAbsent：防止两个线程同时创建 Future，只保留第一个
        CompletableFuture<WeatherDto> winner = inflightRequests.putIfAbsent(requestKey, future);
        if (winner != null) {
            // 其他线程已先创建，取消自己的 Future 避免浪费外部 API 调用
            future.cancel(false);
            try {
                return winner.get(6, TimeUnit.SECONDS);
            } catch (Exception e) {
                log.debug("等待已有 in-flight 请求超时", e);
                return WeatherDto.empty();
            }
        }
        try {
            return future.get(6, TimeUnit.SECONDS);
        } catch (Exception e) {
            log.error("天气请求执行超时", e);
            return WeatherDto.empty();
        } finally {
            inflightRequests.remove(requestKey);
        }
    }

    // ==================== 位置解析 ====================

    private ResolvedWeatherLocation resolveLocation(String location, Map<String, String> config) {
        if (isLatLon(location)) {
            return new ResolvedWeatherLocation(location, location, "");
        }
        // 城市名由用户偏好/配置直接提供，展示名优先用入参，不依赖 Geo 返回字段。
        ResolvedWeatherLocation resolved = lookupGeoLocation(location, config);
        if (resolved == null) {
            return null;
        }
        return new ResolvedWeatherLocation(
                resolved.weatherLocation(), resolved.latLon(), location);
    }

    /**
     * 解析展示用地区名：用户入参城市 > 调用方传入展示名 > 配置默认城市。
     */
    private String resolveDisplayName(
            String rawLocation, String displayName, Map<String, String> config) {
        if (rawLocation != null && !rawLocation.isBlank() && !isLatLon(rawLocation)) {
            return rawLocation.trim();
        }
        if (displayName != null && !displayName.isBlank() && !isLatLon(displayName)) {
            return displayName.trim();
        }
        String configLocation = config.get("weather.location");
        if (configLocation != null && !configLocation.isBlank() && !isLatLon(configLocation)) {
            return configLocation.trim();
        }
        return "";
    }

    /**
     * 缓存命中时补齐展示地区名（旧缓存可能没有 locationName）。
     */
    private WeatherDto withLocationName(WeatherDto weather, String locationName) {
        String target = locationName != null ? locationName : "";
        if (weather == null) {
            return WeatherDto.empty();
        }
        if (target.isBlank() || target.equals(weather.locationName())) {
            return weather;
        }
        return new WeatherDto(
                weather.temp(), weather.feelsLike(), weather.text(), weather.icon(),
                weather.humidity(), weather.windSpeed(), weather.windDir(),
                weather.pressure(), weather.visibility(), weather.uvIndex(),
                weather.sunrise(), weather.sunset(), weather.aqi(), weather.pm2p5(),
                weather.aqiCategory(), weather.updateTime(), weather.healthAdvice(),
                weather.tempMax(), weather.tempMin(), weather.precip(), weather.windScale(),
                weather.textDay(), weather.textNight(),
                weather.hourly(), weather.daily(),
                target
        );
    }

    /**
     * 通过 GeoAPI 查询城市信息（LocationID + 经纬度）
     *
     * 城市不存在属于正常业务场景，返回 null（不抛异常）。
     * 缓存穿透防护：失败结果缓存 10min。
     */
    private ResolvedWeatherLocation lookupGeoLocation(String cityName, Map<String, String> config) {
        ResolvedWeatherLocation cached = weatherCacheStore.findLocation(cityName).orElse(null);
        if (cached != null) {
            return cached;
        }

        if (weatherCacheStore.isLocationMissing(cityName)) {
            return null;
        }

        try {
            String jwt = generateJwt(config);
            String baseUrl = config.get("weather.qweather.url");
            String encoded = URLEncoder.encode(cityName, StandardCharsets.UTF_8);
            URI uri = URI.create(baseUrl + "/geo/v2/city/lookup?location=" + encoded);
            JSONObject result = httpGet(uri, jwt);

            if (result == null || !"200".equals(result.getString("code"))) {
                weatherCacheStore.markLocationMissing(cityName);
                return null;
            }

            JSONArray locations = result.getJSONArray("location");
            if (locations == null || locations.isEmpty()) {
                weatherCacheStore.markLocationMissing(cityName);
                return null;
            }

            JSONObject first = locations.getJSONObject(0);
            String id = first.getString("id");
            String lat = first.getString("lat");
            String lon = first.getString("lon");
            if (id == null || lat == null || lon == null) {
                return null;
            }

            String latLon = lon + "," + lat;
            // Geo 仅用于 LocationID + 经纬度；展示名由调用方用用户提供的城市名覆盖。
            ResolvedWeatherLocation location = new ResolvedWeatherLocation(id, latLon, "");
            weatherCacheStore.saveLocation(cityName, location);
            return location;
        } catch (Exception e) {
            weatherCacheStore.markLocationMissing(cityName);
            return null;
        }
    }

    // ==================== 外部 API 调用 ====================

    private JSONObject fetchApi(String baseUrl, String path, String location, String jwt) {
        try {
            String encoded = URLEncoder.encode(location, StandardCharsets.UTF_8);
            URI uri = URI.create(baseUrl + path + "?location=" + encoded);
            return httpGet(uri, jwt);
        } catch (Exception e) {
            log.error("调用天气 API 失败: {}", path, e);
            return null;
        }
    }

    private JSONObject fetchAirQuality(String baseUrl, String latLon, String jwt) {
        try {
            String[] parts = latLon.split(",");
            if (parts.length != 2) {
                return null;
            }
            URI uri = URI.create(baseUrl + "/airquality/v1/current/" + parts[1].trim() + "/" + parts[0].trim());
            JSONObject json = httpGet(uri, jwt);
            return json != null ? parseAirQualityResponse(json) : null;
        } catch (Exception e) {
            log.error("调用空气质量 API 失败", e);
            return null;
        }
    }

    /**
     * 公共 HTTP GET
     *
     * @return 解析后的 JSONObject；非 2xx 或非 JSON 响应返回 null
     * @throws RuntimeException 网络异常等不可恢复错误
     */
    private JSONObject httpGet(URI uri, String jwt) {
        var headers = new HttpHeaders();
        headers.set("Authorization", "Bearer " + jwt);
        headers.set("Accept", "application/json");
        headers.set("Accept-Encoding", "gzip");

        var response = restTemplate.exchange(uri, HttpMethod.GET, new HttpEntity<>(headers), byte[].class);

        if (response.getStatusCode().is2xxSuccessful() && response.getBody() != null) {
            String body = decompressGzip(response.getBody());
            if (body.trim().startsWith("{")) {
                return JSON.parseObject(body);
            }
        }
        return null;
    }

    // ==================== 响应解析 ====================

    private JSONObject parseAirQualityResponse(JSONObject response) {
        JSONObject result = new JSONObject();
        result.put("code", "200");
        JSONObject now = new JSONObject();

        JSONArray indexes = response.getJSONArray("indexes");
        if (indexes != null) {
            JSONObject aqiEntry = findByCode(indexes, "us-epa");
            if (aqiEntry == null) aqiEntry = findByCode(indexes, "qaqi");
            if (aqiEntry != null) {
                now.put("aqi", getIntSafe(aqiEntry, "aqiDisplay"));
                now.put("category", aqiEntry.getString("category"));
            }
        }

        JSONArray pollutants = response.getJSONArray("pollutants");
        if (pollutants != null) {
            JSONObject pm25 = findByCode(pollutants, "pm2p5");
            if (pm25 != null) {
                JSONObject concentration = pm25.getJSONObject("concentration");
                if (concentration != null) {
                    now.put("pm2p5", getIntSafe(concentration, "value"));
                }
            }
        }

        JSONObject health = response.getJSONObject("health");
        if (health != null) {
            JSONObject advice = health.getJSONObject("advice");
            if (advice != null) {
                now.put("advice", advice.getString("generalPopulation"));
            }
        }

        result.put("now", now);
        return result;
    }

    private JSONObject findByCode(JSONArray array, String code) {
        for (int i = 0; i < array.size(); i++) {
            JSONObject item = array.getJSONObject(i);
            if (code.equals(item.getString("code"))) return item;
        }
        return null;
    }

    private WeatherDto aggregateWeather(
            JSONObject weatherNow,
            JSONObject airNow,
            JSONObject weather7d,
            JSONObject weather24h,
            String locationName) {
        if (weatherNow == null || !"200".equals(weatherNow.getString("code"))) {
            return WeatherDto.empty();
        }
        JSONObject now = weatherNow.getJSONObject("now");
        if (now == null) return WeatherDto.empty();

        JSONObject air = airNow != null && "200".equals(airNow.getString("code"))
                ? airNow.getJSONObject("now") : null;
        JSONObject today = null;
        List<WeatherDto.DailyForecast> dailyForecasts = List.of();
        if (weather7d != null && "200".equals(weather7d.getString("code"))) {
            var daily = weather7d.getJSONArray("daily");
            if (daily != null && !daily.isEmpty()) {
                today = daily.getJSONObject(0);
                dailyForecasts = parseDailyForecasts(daily);
            }
        }
        List<WeatherDto.HourlyForecast> hourlyForecasts = List.of();
        if (weather24h != null && "200".equals(weather24h.getString("code"))) {
            hourlyForecasts = parseHourlyForecasts(weather24h.getJSONArray("hourly"));
        }

        return new WeatherDto(
            now.getDoubleValue("temp"), now.getDoubleValue("feelsLike"),
            now.getString("text"), now.getString("icon"),
            now.getString("humidity") + "%", now.getString("windSpeed") + " km/h",
            now.getString("windDir"), now.getString("pressure") + " hPa",
            now.getString("vis") + " km",
            today != null ? today.getIntValue("uvIndex") : 0,
            today != null ? today.getString("sunrise") : "--",
            today != null ? today.getString("sunset") : "--",
            air != null ? getIntSafe(air, "aqi") : 0,
            air != null ? getIntSafe(air, "pm2p5") : 0,
            air != null ? getStringSafe(air, "category", "--") : "--",
            weatherNow.getString("updateTime"),
            air != null ? getStringSafe(air, "advice", "") : "",
            today != null ? today.getDoubleValue("tempMax") : 0.0,
            today != null ? today.getDoubleValue("tempMin") : 0.0,
            now.getString("precip") + " mm",
            getStringSafe(now, "windScale", "--"),
            today != null ? getStringSafe(today, "textDay", "--") : "--",
            today != null ? getStringSafe(today, "textNight", "--") : "--",
            hourlyForecasts,
            dailyForecasts,
            locationName != null ? locationName : ""
        );
    }

    private List<WeatherDto.HourlyForecast> parseHourlyForecasts(JSONArray hourly) {
        if (hourly == null || hourly.isEmpty()) {
            return List.of();
        }
        int limit = Math.min(hourly.size(), 24);
        ArrayList<WeatherDto.HourlyForecast> items = new ArrayList<>(limit);
        for (int i = 0; i < limit; i++) {
            JSONObject item = hourly.getJSONObject(i);
            if (item == null) {
                continue;
            }
            items.add(new WeatherDto.HourlyForecast(
                    getStringSafe(item, "fxTime", "--"),
                    (int) item.getDoubleValue("temp"),
                    getStringSafe(item, "icon", "999"),
                    getStringSafe(item, "text", "--")
            ));
        }
        return List.copyOf(items);
    }

    private List<WeatherDto.DailyForecast> parseDailyForecasts(JSONArray daily) {
        if (daily == null || daily.isEmpty()) {
            return List.of();
        }
        int limit = Math.min(daily.size(), 7);
        ArrayList<WeatherDto.DailyForecast> items = new ArrayList<>(limit);
        for (int i = 0; i < limit; i++) {
            JSONObject item = daily.getJSONObject(i);
            if (item == null) {
                continue;
            }
            items.add(new WeatherDto.DailyForecast(
                    getStringSafe(item, "fxDate", "--"),
                    (int) item.getDoubleValue("tempMax"),
                    (int) item.getDoubleValue("tempMin"),
                    getStringSafe(item, "iconDay", "999"),
                    getStringSafe(item, "textDay", "--"),
                    getStringSafe(item, "iconNight", "999"),
                    getStringSafe(item, "textNight", "--")
            ));
        }
        return List.copyOf(items);
    }

    // ==================== JWT 生成 ====================

    /**
     * 生成 JWT Token
     *
     * @throws BusinessException 配置不完整或签名失败
     */
    private String generateJwt(Map<String, String> config) {
        String projectId = config.get("weather.qweather.project");
        String credentialId = config.get("weather.qweather.credential");
        String privateKeyPem = config.get("weather.qweather.key");

        if (projectId == null || projectId.isBlank()
                || credentialId == null || credentialId.isBlank()
                || privateKeyPem == null || privateKeyPem.isBlank()) {
            throw new BusinessException(ErrorCode.CONFIG_VALUE_INVALID, "天气服务 JWT 配置不完整");
        }

        String cachedToken = weatherCacheStore.findJwt(credentialId).orElse(null);
        if (cachedToken != null) return cachedToken;

        synchronized (jwtLock) {
            cachedToken = weatherCacheStore.findJwt(credentialId).orElse(null);
            if (cachedToken != null) return cachedToken;

            try {
                PrivateKey privateKey = parseEd25519PrivateKey(privateKeyPem);

                JWSHeader header = new JWSHeader.Builder(JWSAlgorithm.EdDSA).keyID(credentialId).build();
                Instant now = Instant.now();
                JWTClaimsSet claims = new JWTClaimsSet.Builder()
                        .subject(projectId)
                        .issueTime(Date.from(now.minusSeconds(30)))
                        .expirationTime(Date.from(now.plusSeconds(3600)))
                        .build();

                SignedJWT jwt = new SignedJWT(header, claims);
                byte[] keyBytes = privateKey.getEncoded();
                byte[] rawPrivateKey = new byte[32];
                System.arraycopy(keyBytes, keyBytes.length - 32, rawPrivateKey, 0, 32);
                OctetKeyPair okp = new OctetKeyPair.Builder(Curve.Ed25519,
                        Base64URL.encode(new byte[32])).d(Base64URL.encode(rawPrivateKey)).build();

                jwt.sign(new Ed25519Signer(okp));
                String token = jwt.serialize();
                weatherCacheStore.saveJwt(credentialId, token);
                return token;
            } catch (BusinessException e) {
                throw e;
            } catch (Exception e) {
                throw new BusinessException(ErrorCode.INTERNAL_ERROR, "JWT 签名失败: " + e.getMessage());
            }
        }
    }

    private PrivateKey parseEd25519PrivateKey(String pem) throws Exception {
        String base64 = pem
                .replace("-----BEGIN PRIVATE KEY-----", "")
                .replace("-----END PRIVATE KEY-----", "")
                .replace("-----BEGIN EC PRIVATE KEY-----", "")
                .replace("-----END EC PRIVATE KEY-----", "")
                .replaceAll("\\s", "");
        return KeyFactory.getInstance("Ed25519")
                .generatePrivate(new PKCS8EncodedKeySpec(Base64.getDecoder().decode(base64)));
    }

    // ==================== 配置缓存 ====================

    private Map<String, String> loadConfig() {
        Instant now = Instant.now();
        Map<String, String> cached = this.configCache;
        if (cached != null && now.isBefore(this.configCacheExpiry)) return cached;

        synchronized (this) {
            cached = this.configCache;
            if (cached != null && now.isBefore(this.configCacheExpiry)) return cached;

            Map<String, String> newConfig = new ConcurrentHashMap<>();
            try {
                for (String key : CONFIG_KEYS) {
                    configValueProvider.findByKey(key)
                            .or(() -> legacyConfigKey(key))
                            .ifPresent(value -> newConfig.put(key, value));
                }
                newConfig.putIfAbsent("weather.qweather.url", "https://devapi.qweather.com");
                newConfig.putIfAbsent("weather.location", "北京");
            } catch (Exception e) {
                newConfig.clear();
                log.debug("加载天气配置失败，使用空配置", e);
            }
            this.configCache = Map.copyOf(newConfig);
            this.configCacheExpiry = now.plus(CONFIG_CACHE_TTL);
            return this.configCache;
        }
    }

    private Optional<String> legacyConfigKey(String key) {
        String legacyKey = switch (key) {
            case "weather.qweather.url" -> "weather.qweather.base-url";
            case "weather.qweather.project" -> "weather.qweather.project-id";
            case "weather.qweather.credential" -> "weather.qweather.credential-id";
            case "weather.qweather.key" -> "weather.qweather.private-key";
            default -> null;
        };
        return legacyKey == null ? Optional.empty() : configValueProvider.findByKey(legacyKey);
    }

    // ==================== 工具方法 ====================

    private JSONObject getOrNull(CompletableFuture<JSONObject> future) {
        try {
            return future.get(5, TimeUnit.SECONDS);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return null;
        } catch (Exception e) {
            return null;
        }
    }

    private int getIntSafe(JSONObject obj, String key) {
        String val = obj.getString(key);
        if (val == null || val.isBlank()) return 0;
        try { return (int) Double.parseDouble(val); } catch (NumberFormatException e) { return 0; }
    }

    private String getStringSafe(JSONObject obj, String key, String defaultValue) {
        String val = obj.getString(key);
        return val != null ? val : defaultValue;
    }

    private boolean isLatLon(String location) {
        return location != null && COORD_PATTERN.matcher(location.trim()).matches();
    }

    private static final int MAX_DECOMPRESSED_SIZE = 1024 * 1024;

    private String decompressGzip(byte[] data) {
        if (data.length >= 2 && (data[0] & 0xFF) == 0x1f && (data[1] & 0xFF) == 0x8b) {
            try (var gzipIn = new GZIPInputStream(new ByteArrayInputStream(data));
                 var out = new ByteArrayOutputStream()) {
                byte[] buffer = new byte[1024];
                int len;
                int total = 0;
                while ((len = gzipIn.read(buffer)) > 0) {
                    total += len;
                    if (total > MAX_DECOMPRESSED_SIZE) {
                        log.warn("GZIP 解压超过大小限制({} bytes)，丢弃响应", MAX_DECOMPRESSED_SIZE);
                        return "";
                    }
                    out.write(buffer, 0, len);
                }
                return out.toString(StandardCharsets.UTF_8);
            } catch (Exception e) {
                log.debug("GZIP 解压失败，回退原始字节", e);
            }
        }
        return new String(data, StandardCharsets.UTF_8);
    }

    private static RestTemplate createRestTemplate() {
        SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(3000);
        factory.setReadTimeout(5000);
        return new RestTemplate(factory);
    }

}
