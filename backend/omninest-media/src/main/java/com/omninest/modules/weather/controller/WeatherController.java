package com.omninest.modules.weather.controller;

import com.omninest.common.api.ApiResponse;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.preferences.UserPreferenceQuery;
import com.omninest.common.ratelimit.RateLimitService;
import com.omninest.common.security.ClientIpResolver;
import com.omninest.common.security.CurrentUserContext;
import com.omninest.common.security.Permissions;
import com.omninest.modules.weather.dto.UserLocationDto;
import com.omninest.modules.weather.dto.WeatherDto;
import com.omninest.modules.weather.service.UserLocationService;
import com.omninest.modules.weather.service.WeatherService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import java.time.Duration;
import java.util.Map;
import java.util.UUID;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import lombok.RequiredArgsConstructor;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * 天气接口
 *
 * 代理和风天气 API，前端通过此接口获取天气数据。
 * 位置优先级：Redis GPS（设备上报） > 前端 GPS 坐标 > 用户偏好城市 > 配置中心默认值
 */
@Tag(name = "天气", description = "天气信息查询")
@RestController
@RequestMapping("/api/v1/weather")
@RequiredArgsConstructor
public class WeatherController {

    private static final String WEATHER_PREF_SCOPE = "weather";
    private static final String LOCATION_PREF_KEY = "location";
    private static final String LOCALE_PREF_SCOPE = "locale.v1";
    private static final String LANGUAGE_PREF_KEY = "language";
    private final WeatherService weatherService;
    private final UserLocationService userLocationService;
    private final UserPreferenceQuery userPreferenceQuery;
    private final CurrentUserContext currentUserContext;
    private final RateLimitService rateLimitService;
    private final ClientIpResolver clientIpResolver;

    /**
     * 获取实时天气
     *
     * 位置优先级：Redis GPS（设备上报） > 前端 GPS 坐标 > 用户偏好城市 > 配置中心默认值
     * 注意：前端传城市名不会覆盖用户偏好，仅接受经纬度格式的 GPS 坐标
     *
     * @param location 经纬度坐标（如"116.41,39.92"），可选；城市名参数会被忽略
     */
    @Operation(summary = "获取实时天气", description = "根据用户位置获取实时天气信息，位置优先级：Redis GPS > 前端坐标 > 用户偏好城市 > 默认值")
    @GetMapping("/realtime")
    @PreAuthorize("hasAnyAuthority('" + Permissions.ACTIVITY_READ + "', '" + Permissions.PREFERENCE_READ + "')")
    public ApiResponse<WeatherDto> getRealtimeWeather(
            @RequestParam(required = false) String location,
            HttpServletRequest httpRequest) {
        // 用户级额度兜住"轮换出口 IP 绕开限流"，IP 级只做更高的总量兜底：
        // 家庭/办公 NAT 共用出口时，同一个 IP 桶不再让成员互相挤占。
        UUID userId = currentUserContext.requireCurrentUserId();
        if (!rateLimitService.tryAcquire("weather:user:" + userId, 30, Duration.ofMinutes(1))
                || !rateLimitService.tryAcquire(
                        "weather:" + resolveClientIp(httpRequest), 120, Duration.ofMinutes(1))) {
            throw new BusinessException(ErrorCode.RATE_LIMITED, "天气查询过于频繁，请稍后再试");
        }

        // 优先级：Redis GPS（设备上报） > 前端 GPS 坐标 > 用户偏好城市 > 配置中心默认值
        String lang = getPreferenceLanguage(userId);
        // 1. 最高优先级：设备上报的 GPS 坐标（最精确、最实时）
        String resolvedLocation = userLocationService.getLocation(userId);
        // 2. 无 Redis GPS 时，使用前端传参（仅接受坐标格式，拒绝城市名覆盖）
        if (resolvedLocation == null || resolvedLocation.isBlank()) {
            if (location != null && !location.isBlank() && isLatLon(location.trim())) {
                resolvedLocation = location.trim();
            }
        }
        // 3. 用户偏好城市：仅在设备没有 GPS、前端也没有坐标时作为查询位置。
        // GPS 坐标的展示名由 GeoAPI 反查，不能再拿偏好城市覆盖，否则会出现
        // 人在北京、界面显示上海（或配置默认北京）的错位。
        String preferenceLocation = getPreferenceLocation(userId);
        if (resolvedLocation == null || resolvedLocation.isBlank()) {
            resolvedLocation = preferenceLocation;
        }
        WeatherDto weather = weatherService.getRealtimeWeather(resolvedLocation, null, lang);
        return ApiResponse.success(weather);
    }

    /**
     * 判断查询位置是否为经纬度坐标。
     *
     * <p>GPS 坐标可能恰好是整数度（如 {@code 116,40}），不能要求必须带小数；
     * 越界坐标按普通地名处理，避免把非法值透传给上游。</p>
     */
    private boolean isLatLon(String location) {
        Matcher matcher = LAT_LON_PATTERN.matcher(location);
        if (!matcher.matches()) {
            return false;
        }
        double latitude = Double.parseDouble(matcher.group(1));
        double longitude = Double.parseDouble(matcher.group(2));
        return Math.abs(latitude) <= 90 && Math.abs(longitude) <= 180;
    }

    private static final Pattern LAT_LON_PATTERN =
            Pattern.compile("^(-?\\d{1,3}(?:\\.\\d+)?),\\s*(-?\\d{1,3}(?:\\.\\d+)?)$");

    private String resolveClientIp(HttpServletRequest request) {
        return clientIpResolver.resolve(
                request.getRemoteAddr(),
                request.getHeader("X-Forwarded-For"),
                request.getHeader("X-Real-IP")
        );
    }

    /**
     * 从用户偏好中读取天气城市设置
     */
    private String getPreferenceLocation(UUID userId) {
        Map<String, Object> prefs = userPreferenceQuery.findValues(userId, WEATHER_PREF_SCOPE);
        Object val = prefs.get(LOCATION_PREF_KEY);
        if (val instanceof String s && !s.isBlank()) {
            return s.trim();
        }
        return null;
    }

    /**
     * 从用户偏好中读取界面语言。
     *
     * 客户端切换语言时会把 {@code locale.v1} 作用域同步到服务端，天气状况文案
     * 因此按这份偏好向外部 API 请求，而不是按调用方传参或服务端默认值——
     * 后者会让中文界面里出现英文的"晴/多云"文本。
     */
    private String getPreferenceLanguage(UUID userId) {
        Map<String, Object> prefs = userPreferenceQuery.findValues(userId, LOCALE_PREF_SCOPE);
        Object val = prefs.get(LANGUAGE_PREF_KEY);
        if (val instanceof String s && !s.isBlank()) {
            return s.trim();
        }
        return null;
    }

    /**
     * 上报用户地理位置
     *
     * 移动端/桌面端获取到 GPS 坐标后调用此接口上报，
     * 天气查询时自动使用最近上报的位置。
     */
    @Operation(summary = "上报地理位置", description = "移动端/桌面端获取到 GPS 坐标后调用此接口上报，天气查询时自动使用最近上报的位置")
    @PostMapping("/location")
    @PreAuthorize("hasAuthority('" + Permissions.ACTIVITY_WRITE + "')")
    public ApiResponse<Void> reportLocation(
            @Valid @RequestBody UserLocationDto dto,
            HttpServletRequest httpRequest) {
        UUID userId = currentUserContext.requireCurrentUserId();
        // 与实时天气同一口径：用户级额度防绕过，IP 级只做更高的总量兜底。
        if (!rateLimitService.tryAcquire("weather:loc:user:" + userId, 10, Duration.ofMinutes(1))
                || !rateLimitService.tryAcquire(
                        "weather:loc:" + resolveClientIp(httpRequest), 40, Duration.ofMinutes(1))) {
            throw new BusinessException(ErrorCode.RATE_LIMITED, "位置上报过于频繁");
        }
        userLocationService.saveLocation(userId, dto.latitude(), dto.longitude(), dto.source());
        return ApiResponse.success(null);
    }
}
