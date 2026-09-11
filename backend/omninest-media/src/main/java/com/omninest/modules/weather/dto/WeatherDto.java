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
    List<DailyForecast> daily
) {

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
        return new WeatherDto(
            0.0, 0.0, "未知", "999",
            "--", "--", "--", "--", "--",
            0, "--", "--",
            0, 0, "--", "", "",
            0.0, 0.0, "--", "--", "--", "--",
            List.of(), List.of()
        );
    }
}
