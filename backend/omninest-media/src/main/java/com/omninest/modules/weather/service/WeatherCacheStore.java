package com.omninest.modules.weather.service;

import com.omninest.modules.weather.dto.WeatherDto;
import java.util.Optional;

/**
 * 天气业务缓存端口，隔离缓存键、序列化格式和存储实现。
 *
 * @author OmniNest
 */
public interface WeatherCacheStore {

    /**
     * 查询天气服务 JWT。
     *
     * @param credentialId 凭据标识
     * @return 缓存中的 JWT
     */
    Optional<String> findJwt(String credentialId);

    /**
     * 保存天气服务 JWT。
     *
     * @param credentialId 凭据标识
     * @param token JWT
     */
    void saveJwt(String credentialId, String token);

    /**
     * 查询城市解析结果。
     *
     * @param cityName 城市名称或位置标识
     * @return 城市解析结果
     */
    Optional<ResolvedWeatherLocation> findLocation(String cityName);

    /**
     * 判断城市是否处于解析负命中有效期内。
     *
     * @param cityName 城市名称或位置标识
     * @return 处于负命中有效期时返回 true
     */
    boolean isLocationMissing(String cityName);

    /**
     * 保存城市解析结果并清除对应负命中记录。
     *
     * @param cityName 城市名称或位置标识
     * @param location 城市解析结果
     */
    void saveLocation(String cityName, ResolvedWeatherLocation location);

    /**
     * 标记城市解析负命中。
     *
     * @param cityName 城市名称或位置标识
     */
    void markLocationMissing(String cityName);

    /**
     * 查询天气聚合结果。
     *
     * @param latLon 经度和纬度
     * @return 天气聚合结果
     */
    Optional<WeatherDto> findWeather(String latLon);

    /**
     * 保存天气聚合结果。
     *
     * @param latLon 经度和纬度
     * @param weather 天气聚合结果
     */
    void saveWeather(String latLon, WeatherDto weather);

    /**
     * 天气 API 位置标识与经纬度组合。
     *
     * @param weatherLocation 天气 API 使用的位置标识
     * @param latLon 经度和纬度
     * @param locationName 可读地区名（城市名），GPS 直连时可能为空
     */
    record ResolvedWeatherLocation(String weatherLocation, String latLon, String locationName) {

        public ResolvedWeatherLocation(String weatherLocation, String latLon) {
            this(weatherLocation, latLon, "");
        }
    }
}
