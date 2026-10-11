package com.omninest.modules.weather.infrastructure;

import com.omninest.common.json.JsonSupport;
import com.omninest.common.util.RedisUtil;
import com.omninest.modules.weather.dto.WeatherDto;
import com.omninest.modules.weather.service.WeatherCacheStore;
import com.omninest.modules.weather.service.WeatherCacheStore.ResolvedWeatherLocation;
import java.time.Duration;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import tools.jackson.databind.JsonNode;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

/**
 * 使用 Redis 保存天气认证、位置解析和天气聚合缓存。
 *
 * @author OmniNest
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class RedisWeatherCacheStore implements WeatherCacheStore {

    private static final String JWT_KEY_PREFIX = "weather:jwt:";
    private static final String GEO_KEY_PREFIX = "weather:geo:";
    private static final String GEO_MISS_KEY_PREFIX = "weather:geo:miss:";
    private static final String WEATHER_KEY_PREFIX = "weather:data:";
    private static final String GEO_MISS_SENTINEL = "__MISS__";

    private static final Duration JWT_TTL = Duration.ofMinutes(55);
    private static final Duration GEO_TTL = Duration.ofHours(24);
    private static final Duration GEO_MISS_TTL = Duration.ofMinutes(10);
    private static final Duration WEATHER_TTL = Duration.ofMinutes(10);

    private final RedisUtil redisUtil;

    /**
     * 查询天气服务 JWT。
     *
     * @param credentialId 凭据标识
     * @return 缓存中的 JWT
     */
    @Override
    public Optional<String> findJwt(String credentialId) {
        return read(JWT_KEY_PREFIX + credentialId, "读取天气 JWT 缓存失败");
    }

    /**
     * 保存天气服务 JWT。
     *
     * @param credentialId 凭据标识
     * @param token JWT
     */
    @Override
    public void saveJwt(String credentialId, String token) {
        write(JWT_KEY_PREFIX + credentialId, token, JWT_TTL, "保存天气 JWT 缓存失败");
    }

    /**
     * 查询城市解析结果。
     *
     * @param cityName 城市名称或位置标识
     * @return 城市解析结果
     */
    @Override
    public Optional<ResolvedWeatherLocation> findLocation(String cityName) {
        Optional<String> cached = read(GEO_KEY_PREFIX + cityName, "读取天气位置缓存失败");
        if (cached.isEmpty()) {
            return Optional.empty();
        }
        String[] parts = cached.orElseThrow().split("\\|", 3);
        if (parts.length < 2 || parts[0].isBlank() || parts[1].isBlank()) {
            log.warn("天气位置缓存格式无效");
            return Optional.empty();
        }
        String locationName = parts.length >= 3 ? parts[2] : "";
        return Optional.of(new ResolvedWeatherLocation(parts[0], parts[1], locationName));
    }

    /**
     * 判断城市是否处于解析负命中有效期内。
     *
     * @param cityName 城市名称或位置标识
     * @return 处于负命中有效期时返回 true
     */
    @Override
    public boolean isLocationMissing(String cityName) {
        return read(GEO_MISS_KEY_PREFIX + cityName, "读取天气位置负命中缓存失败")
                .filter(GEO_MISS_SENTINEL::equals)
                .isPresent();
    }

    /**
     * 保存城市解析结果并清除对应负命中记录。
     *
     * @param cityName 城市名称或位置标识
     * @param location 城市解析结果
     */
    @Override
    public void saveLocation(String cityName, ResolvedWeatherLocation location) {
        String name = location.locationName() == null ? "" : location.locationName();
        String value = name.isBlank()
                ? location.weatherLocation() + "|" + location.latLon()
                : location.weatherLocation() + "|" + location.latLon() + "|" + name;
        write(GEO_KEY_PREFIX + cityName, value, GEO_TTL, "保存天气位置缓存失败");
        delete(GEO_MISS_KEY_PREFIX + cityName, "清除天气位置负命中缓存失败");
    }

    /**
     * 标记城市解析负命中。
     *
     * @param cityName 城市名称或位置标识
     */
    @Override
    public void markLocationMissing(String cityName) {
        write(
                GEO_MISS_KEY_PREFIX + cityName,
                GEO_MISS_SENTINEL,
                GEO_MISS_TTL,
                "保存天气位置负命中缓存失败"
        );
    }

    /**
     * 查询天气聚合结果。
     *
     * @param cacheKey 位置与语言的组合键（{@code 经度,纬度:lang}）
     * @return 天气聚合结果
     */
    @Override
    public Optional<WeatherDto> findWeather(String cacheKey) {
        Optional<String> cached = read(WEATHER_KEY_PREFIX + cacheKey, "读取天气数据缓存失败");
        if (cached.isEmpty()) {
            return Optional.empty();
        }
        try {
            return Optional.of(parseWeather(cached.orElseThrow()));
        } catch (RuntimeException exception) {
            log.warn("天气数据缓存格式无效", exception);
            return Optional.empty();
        }
    }

    /**
     * 保存天气聚合结果。
     *
     * @param cacheKey 位置与语言的组合键（{@code 经度,纬度:lang}）
     * @param weather 天气聚合结果
     */
    @Override
    public void saveWeather(String cacheKey, WeatherDto weather) {
        write(
                WEATHER_KEY_PREFIX + cacheKey,
                serializeWeather(weather),
                WEATHER_TTL,
                "保存天气数据缓存失败"
        );
    }

    private Optional<String> read(String key, String failureMessage) {
        try {
            String value = redisUtil.get(key);
            if (value == null || value.isBlank()) {
                return Optional.empty();
            }
            return Optional.of(value);
        } catch (RuntimeException exception) {
            log.debug(failureMessage, exception);
            return Optional.empty();
        }
    }

    private void write(String key, String value, Duration ttl, String failureMessage) {
        try {
            redisUtil.set(key, value, ttl);
        } catch (RuntimeException exception) {
            log.debug(failureMessage, exception);
        }
    }

    private void delete(String key, String failureMessage) {
        try {
            redisUtil.delete(key);
        } catch (RuntimeException exception) {
            log.debug(failureMessage, exception);
        }
    }

    private String serializeWeather(WeatherDto weather) {
        Map<String, Object> json = new LinkedHashMap<>();
        json.put("temp", weather.temp());
        json.put("feelsLike", weather.feelsLike());
        json.put("text", weather.text());
        json.put("icon", weather.icon());
        json.put("humidity", weather.humidity());
        json.put("windSpeed", weather.windSpeed());
        json.put("windDir", weather.windDir());
        json.put("pressure", weather.pressure());
        json.put("visibility", weather.visibility());
        json.put("uvIndex", weather.uvIndex());
        json.put("sunrise", weather.sunrise());
        json.put("sunset", weather.sunset());
        json.put("aqi", weather.aqi());
        json.put("pm2p5", weather.pm2p5());
        json.put("aqiCategory", weather.aqiCategory());
        json.put("updateTime", weather.updateTime());
        json.put("healthAdvice", weather.healthAdvice());
        json.put("tempMax", weather.tempMax());
        json.put("tempMin", weather.tempMin());
        json.put("precip", weather.precip());
        json.put("windScale", weather.windScale());
        json.put("textDay", weather.textDay());
        json.put("textNight", weather.textNight());
        json.put("hourly", serializeHourly(weather.hourly()));
        json.put("daily", serializeDaily(weather.daily()));
        json.put("locationName", weather.locationName() != null ? weather.locationName() : "");
        return JsonSupport.toJson(json);
    }

    private List<Map<String, Object>> serializeHourly(List<WeatherDto.HourlyForecast> hourly) {
        List<Map<String, Object>> array = new ArrayList<>();
        if (hourly == null) {
            return array;
        }
        for (WeatherDto.HourlyForecast item : hourly) {
            Map<String, Object> json = new LinkedHashMap<>();
            json.put("time", item.time());
            json.put("temp", item.temp());
            json.put("icon", item.icon());
            json.put("text", item.text());
            array.add(json);
        }
        return array;
    }

    private List<Map<String, Object>> serializeDaily(List<WeatherDto.DailyForecast> daily) {
        List<Map<String, Object>> array = new ArrayList<>();
        if (daily == null) {
            return array;
        }
        for (WeatherDto.DailyForecast item : daily) {
            Map<String, Object> json = new LinkedHashMap<>();
            json.put("date", item.date());
            json.put("tempMax", item.tempMax());
            json.put("tempMin", item.tempMin());
            json.put("iconDay", item.iconDay());
            json.put("textDay", item.textDay());
            json.put("iconNight", item.iconNight());
            json.put("textNight", item.textNight());
            array.add(json);
        }
        return array;
    }

    private WeatherDto parseWeather(String cached) {
        JsonNode json = JsonSupport.readTree(cached);
        return new WeatherDto(
                json.path("temp").asDouble(),
                json.path("feelsLike").asDouble(),
                json.path("text").asString(null),
                json.path("icon").asString(null),
                json.path("humidity").asString(null),
                json.path("windSpeed").asString(null),
                json.path("windDir").asString(null),
                json.path("pressure").asString(null),
                json.path("visibility").asString(null),
                json.path("uvIndex").asInt(),
                json.path("sunrise").asString(null),
                json.path("sunset").asString(null),
                json.path("aqi").asInt(),
                json.path("pm2p5").asInt(),
                json.path("aqiCategory").asString(null),
                json.path("updateTime").asString(null),
                json.path("healthAdvice").asString(""),
                json.path("tempMax").asDouble(),
                json.path("tempMin").asDouble(),
                json.path("precip").asString("--"),
                json.path("windScale").asString("--"),
                json.path("textDay").asString("--"),
                json.path("textNight").asString("--"),
                parseHourly(json.path("hourly")),
                parseDaily(json.path("daily")),
                json.path("locationName").asString("")
        );
    }

    private List<WeatherDto.HourlyForecast> parseHourly(JsonNode array) {
        if (array == null || !array.isArray() || array.isEmpty()) {
            return List.of();
        }
        List<WeatherDto.HourlyForecast> items = new ArrayList<>(array.size());
        for (int i = 0; i < array.size(); i++) {
            JsonNode item = array.get(i);
            if (item == null || !item.isObject()) {
                continue;
            }
            items.add(new WeatherDto.HourlyForecast(
                    item.path("time").asString(null),
                    item.path("temp").asInt(),
                    item.path("icon").asString(null),
                    item.path("text").asString(null)
            ));
        }
        return List.copyOf(items);
    }

    private List<WeatherDto.DailyForecast> parseDaily(JsonNode array) {
        if (array == null || !array.isArray() || array.isEmpty()) {
            return List.of();
        }
        List<WeatherDto.DailyForecast> items = new ArrayList<>(array.size());
        for (int i = 0; i < array.size(); i++) {
            JsonNode item = array.get(i);
            if (item == null || !item.isObject()) {
                continue;
            }
            items.add(new WeatherDto.DailyForecast(
                    item.path("date").asString(null),
                    item.path("tempMax").asInt(),
                    item.path("tempMin").asInt(),
                    item.path("iconDay").asString(null),
                    item.path("textDay").asString(null),
                    item.path("iconNight").asString(null),
                    item.path("textNight").asString(null)
            ));
        }
        return List.copyOf(items);
    }
}
