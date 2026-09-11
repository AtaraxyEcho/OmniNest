package com.omninest.modules.weather.controller;

import com.omninest.common.api.ApiResponse;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.preferences.UserPreferenceQuery;
import com.omninest.common.ratelimit.RateLimitService;
import com.omninest.common.security.ClientIpResolver;
import com.omninest.common.security.CurrentUserContext;
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
import lombok.RequiredArgsConstructor;
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
    public ApiResponse<WeatherDto> getRealtimeWeather(
            @RequestParam(required = false) String location,
            HttpServletRequest httpRequest) {
        // 按 IP 限流：每分钟 30 次（天气查询会触发多个外部 API 调用）
        String ip = resolveClientIp(httpRequest);
        if (!rateLimitService.tryAcquire("weather:" + ip, 30, Duration.ofMinutes(1))) {
            throw new BusinessException(ErrorCode.RATE_LIMITED, "天气查询过于频繁，请稍后再试");
        }

        // 优先级：Redis GPS（设备上报） > 前端 GPS 坐标 > 用户偏好城市 > 配置中心默认值
        String resolvedLocation = null;
        String displayName = null;
        try {
            UUID userId = currentUserContext.requireCurrentUserId();
            // 1. 最高优先级：设备上报的 GPS 坐标（最精确、最实时）
            resolvedLocation = userLocationService.getLocation(userId);
            // 2. 无 Redis GPS 时，使用前端传参（仅接受坐标格式，拒绝城市名覆盖）
            if (resolvedLocation == null || resolvedLocation.isBlank()) {
                if (location != null && !location.isBlank() && isLatLon(location.trim())) {
                    resolvedLocation = location.trim();
                }
            }
            // 3. 用户偏好城市（用于展示名；也可能是 API 查询位置）
            String preferenceLocation = getPreferenceLocation(userId);
            if (resolvedLocation == null || resolvedLocation.isBlank()) {
                resolvedLocation = preferenceLocation;
            } else if (preferenceLocation != null
                    && !preferenceLocation.isBlank()
                    && !isLatLon(preferenceLocation)) {
                // GPS 已定位时仍用用户设置的城市名作为展示地区
                displayName = preferenceLocation;
            }
        } catch (Exception e) {
            // 未登录，前端坐标可直接使用
            if (location != null && !location.isBlank() && isLatLon(location.trim())) {
                resolvedLocation = location.trim();
            }
        }
        WeatherDto weather = weatherService.getRealtimeWeather(resolvedLocation, displayName);
        return ApiResponse.success(weather);
    }

    private boolean isLatLon(String location) {
        return location.matches("^-?\\d{1,3}\\.\\d+,\\s*-?\\d{1,3}\\.\\d+$");
    }

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
     * 上报用户地理位置
     *
     * 移动端/桌面端获取到 GPS 坐标后调用此接口上报，
     * 天气查询时自动使用最近上报的位置。
     */
    @Operation(summary = "上报地理位置", description = "移动端/桌面端获取到 GPS 坐标后调用此接口上报，天气查询时自动使用最近上报的位置")
    @PostMapping("/location")
    public ApiResponse<Void> reportLocation(
            @Valid @RequestBody UserLocationDto dto,
            HttpServletRequest httpRequest) {
        String ip = resolveClientIp(httpRequest);
        if (!rateLimitService.tryAcquire("weather:loc:" + ip, 10, Duration.ofMinutes(1))) {
            throw new BusinessException(ErrorCode.RATE_LIMITED, "位置上报过于频繁");
        }
        UUID userId = currentUserContext.requireCurrentUserId();
        userLocationService.saveLocation(userId, dto.latitude(), dto.longitude(), dto.source());
        return ApiResponse.success(null);
    }
}
