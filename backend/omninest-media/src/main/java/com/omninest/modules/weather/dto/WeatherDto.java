package com.omninest.modules.weather.dto;

import java.util.List;

/**
 * 天气数据传输对象
 *
 * 含实时观测、今日摘要、逐小时与一周预报。
 */
public record WeatherDto(
    double temp,
    double feelsLike,
    String text,
    String icon,
    String humidity,
    String windSpeed,
    String windDir,
    String pressure,
    String visibility,
    int uvIndex,
    String sunrise,
    String sunset,
    int aqi,
    int pm2p5,
    String aqiCategory,
    String updateTime,
    String healthAdvice,
    double tempMax,
    double tempMin,
    String precip,
    String windScale,
    String textDay,
    String textNight,
    List<HourlyForecast> hourly,
    List<DailyForecast> daily,
    String locationName,
    String status
) {

    /** 正常天气数据。 */
    public static final String STATUS_OK = "OK";
    /** 管理员未启用天气能力。 */
    public static final String STATUS_DISABLED = "DISABLED";
    /** 城市/经纬度无法解析。 */
    public static final String STATUS_LOCATION_NOT_FOUND = "LOCATION_NOT_FOUND";
    /** 上游超时、网络失败或返回业务错误。 */
    public static final String STATUS_UPSTREAM_ERROR = "UPSTREAM_ERROR";

    /** 逐小时预报条目。 */
    public record HourlyForecast(
        String time,
        int temp,
        String icon,
        String text
    ) {
    }

    /** 逐日预报条目。 */
    public record DailyForecast(
        String date,
        int tempMax,
        int tempMin,
        String iconDay,
        String textDay,
        String iconNight,
        String textNight
    ) {
    }

    /**
     * 返回空数据（用于未启用或获取失败时）
     */
    public static WeatherDto empty() {
        return degraded(STATUS_UPSTREAM_ERROR);
    }

    /** 天气能力未启用时的空数据。 */
    public static WeatherDto disabled() {
        return degraded(STATUS_DISABLED);
    }

    /** 位置无法解析时的空数据。 */
    public static WeatherDto locationNotFound() {
        return degraded(STATUS_LOCATION_NOT_FOUND);
    }

    /** 上游超时或失败时的空数据。 */
    public static WeatherDto upstreamError() {
        return degraded(STATUS_UPSTREAM_ERROR);
    }

    private static WeatherDto degraded(String status) {
        return new WeatherDto(
            0.0, 0.0, "未知", "999",
            "--", "--", "--", "--", "--",
            0, "--", "--",
            0, 0, "--", "", "",
            0.0, 0.0, "--", "--", "--", "--",
            List.of(), List.of(), "",
            status
        );
    }
}
