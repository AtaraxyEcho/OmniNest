package com.omninest.modules.weather.infrastructure;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.alibaba.fastjson2.JSON;
import com.alibaba.fastjson2.JSONObject;
import com.omninest.common.util.RedisUtil;
import com.omninest.modules.weather.dto.WeatherDto;
import com.omninest.modules.weather.service.WeatherCacheStore.ResolvedWeatherLocation;
import java.time.Duration;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.Mockito;

/**
 * 验证 Redis 天气缓存适配器的数据兼容性和有效期。
 *
 * @author OmniNest
 */
class RedisWeatherCacheStoreTest {

    private static final String CREDENTIAL_ID = "credential-1";
    private static final String CITY_NAME = "贵阳";
    private static final String LAT_LON = "106.71,26.65";

    private final RedisUtil redisUtil = Mockito.mock(RedisUtil.class);
    private final RedisWeatherCacheStore store = new RedisWeatherCacheStore(redisUtil);

    @Test
    void jwtCachePreservesKeyAndTtl() {
        store.saveJwt(CREDENTIAL_ID, "signed-token");

        verify(redisUtil).set(
                "weather:jwt:" + CREDENTIAL_ID,
                "signed-token",
                Duration.ofMinutes(55)
        );
    }

    @Test
    void locationCachePreservesPayloadAndClearsMiss() {
        ResolvedWeatherLocation location = new ResolvedWeatherLocation("101260501", LAT_LON);

        store.saveLocation(CITY_NAME, location);

        verify(redisUtil).set(
                "weather:geo:" + CITY_NAME,
                "101260501|" + LAT_LON,
                Duration.ofHours(24)
        );
        verify(redisUtil).delete("weather:geo:miss:" + CITY_NAME);
    }

    @Test
    void locationCacheReadsExistingPayloadAndMissSentinel() {
        when(redisUtil.get("weather:geo:" + CITY_NAME)).thenReturn("101260501|" + LAT_LON);
        when(redisUtil.get("weather:geo:miss:" + CITY_NAME)).thenReturn("__MISS__");

        ResolvedWeatherLocation location = store.findLocation(CITY_NAME).orElseThrow();

        assertThat(location.weatherLocation()).isEqualTo("101260501");
        assertThat(location.latLon()).isEqualTo(LAT_LON);
        assertThat(store.isLocationMissing(CITY_NAME)).isTrue();
    }

    @Test
    void locationMissPreservesSentinelAndTtl() {
        store.markLocationMissing(CITY_NAME);

        verify(redisUtil).set(
                "weather:geo:miss:" + CITY_NAME,
                "__MISS__",
                Duration.ofMinutes(10)
        );
    }

    @Test
    void weatherCacheReadsExistingJsonShape() {
        when(redisUtil.get("weather:data:" + LAT_LON)).thenReturn("""
                {
                  "temp":22.5,
                  "feelsLike":23.0,
                  "text":"多云",
                  "icon":"101",
                  "humidity":"65%",
                  "windSpeed":"6 km/h",
                  "windDir":"东风",
                  "pressure":"1012 hPa",
                  "visibility":"15 km",
                  "uvIndex":5,
                  "sunrise":"06:00",
                  "sunset":"19:30",
                  "aqi":46,
                  "pm2p5":11,
                  "aqiCategory":"Good",
                  "updateTime":"2026-07-22T12:00:00+08:00",
                  "healthAdvice":"适宜户外活动",
                  "tempMax":27.0,
                  "tempMin":18.0,
                  "precip":"0.0 mm",
                  "windScale":"2",
                  "textDay":"多云",
                  "textNight":"晴"
                }
                """);

        WeatherDto weather = store.findWeather(LAT_LON).orElseThrow();

        assertThat(weather.temp()).isEqualTo(22.5);
        assertThat(weather.text()).isEqualTo("多云");
        assertThat(weather.aqi()).isEqualTo(46);
        assertThat(weather.tempMax()).isEqualTo(27.0);
        assertThat(weather.textNight()).isEqualTo("晴");
    }

    @Test
    void weatherCacheWritesCompleteJsonShapeAndTtl() {
        ArgumentCaptor<String> payloadCaptor = ArgumentCaptor.forClass(String.class);
        WeatherDto weather = weather();

        store.saveWeather(LAT_LON, weather);

        verify(redisUtil).set(
                Mockito.eq("weather:data:" + LAT_LON),
                payloadCaptor.capture(),
                Mockito.eq(Duration.ofMinutes(10))
        );
        JSONObject payload = JSON.parseObject(payloadCaptor.getValue());
        assertThat(payload).containsKeys(
                "temp",
                "feelsLike",
                "text",
                "icon",
                "humidity",
                "windSpeed",
                "windDir",
                "pressure",
                "visibility",
                "uvIndex",
                "sunrise",
                "sunset",
                "aqi",
                "pm2p5",
                "aqiCategory",
                "updateTime",
                "healthAdvice",
                "tempMax",
                "tempMin",
                "precip",
                "windScale",
                "textDay",
                "textNight",
                "hourly",
                "daily"
        );
        assertThat(payload.getJSONArray("hourly")).hasSize(1);
        assertThat(payload.getJSONArray("daily")).hasSize(1);
        assertThat(payload.getString("text")).isEqualTo(weather.text());
    }

    private WeatherDto weather() {
        return new WeatherDto(
                22.5,
                23.0,
                "多云",
                "101",
                "65%",
                "6 km/h",
                "东风",
                "1012 hPa",
                "15 km",
                5,
                "06:00",
                "19:30",
                46,
                11,
                "Good",
                "2026-07-22T12:00:00+08:00",
                "适宜户外活动",
                27.0,
                18.0,
                "0.0 mm",
                "2",
                "多云",
                "晴",
                java.util.List.of(
                        new WeatherDto.HourlyForecast("2026-07-22T13:00+08:00", 22, "101", "多云")
                ),
                java.util.List.of(
                        new WeatherDto.DailyForecast(
                                "2026-07-22", 27, 18, "101", "多云", "150", "晴"
                        )
                ),
                "贵阳"
        );
    }
}
