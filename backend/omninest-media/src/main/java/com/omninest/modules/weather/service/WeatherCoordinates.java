package com.omninest.modules.weather.service;

import java.util.Locale;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * 天气坐标的规范化与格式化。
 *
 * <p>坐标同时是 GeoAPI 入参和 Redis 缓存键：保存与读取必须用同一份格式化，
 * 否则 GPS 的米级漂移会逐次击穿缓存，而极小坐标经 {@code Double.toString} 输出成
 * 科学计数法（如 {@code 5.0E-5}）后还会被坐标正则判成城市名。</p>
 *
 * <p>保留两位小数约 1.1km 网格，与天气预报的空间粒度一致。</p>
 *
 * @author OmniNest
 */
final class WeatherCoordinates {

    /** 与 {@code WeatherService}/{@code WeatherController} 的坐标口径一致：经度在前。 */
    private static final Pattern COORD_PATTERN =
            Pattern.compile("^(-?\\d{1,3}(?:\\.\\d+)?),\\s*(-?\\d{1,3}(?:\\.\\d+)?)$");

    private WeatherCoordinates() {
    }

    /**
     * 按固定精度格式化坐标，消除科学计数法并稳定缓存键。
     *
     * @param lon 经度
     * @param lat 纬度
     * @return {@code "经度,纬度"}，两位小数
     */
    static String format(double lon, double lat) {
        return String.format(Locale.ROOT, "%.2f,%.2f", lon, lat);
    }

    /**
     * 归一化坐标字符串；不是坐标时原样返回。
     *
     * @param location 坐标或城市名
     * @return 坐标为规范化结果，其余原样返回
     */
    static String normalize(String location) {
        if (location == null) {
            return null;
        }
        Matcher matcher = COORD_PATTERN.matcher(location.trim());
        if (!matcher.matches()) {
            return location;
        }
        double lon = Double.parseDouble(matcher.group(1));
        double lat = Double.parseDouble(matcher.group(2));
        if (Math.abs(lon) > 180 || Math.abs(lat) > 90) {
            return location;
        }
        return format(lon, lat);
    }
}
