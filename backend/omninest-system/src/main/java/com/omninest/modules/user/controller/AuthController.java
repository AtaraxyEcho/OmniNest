package com.omninest.modules.user.controller;

import com.omninest.common.api.ApiResponse;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.ratelimit.RateLimitService;
import com.omninest.common.security.BrowserSecurityPolicy;
import com.omninest.common.security.ClientIpResolver;
import com.omninest.common.security.RegistrationPolicy;
import com.omninest.modules.user.dto.AuthTokenResponse;
import com.omninest.modules.user.dto.LoginRequest;
import com.omninest.modules.user.dto.RefreshRequest;
import com.omninest.modules.user.dto.RegisterRequest;
import com.omninest.modules.user.dto.TwoFactorDtos.TwoFactorBootstrapEnableRequest;
import com.omninest.modules.user.dto.TwoFactorDtos.TwoFactorBootstrapEnableResponse;
import com.omninest.modules.user.dto.TwoFactorDtos.TwoFactorBootstrapSetupRequest;
import com.omninest.modules.user.dto.TwoFactorDtos.TwoFactorFinalizeRequest;
import com.omninest.modules.user.dto.TwoFactorDtos.TwoFactorLoginRequest;
import com.omninest.modules.user.dto.TwoFactorDtos.TwoFactorSetupResponse;
import com.omninest.modules.user.service.AuthService;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.validation.Valid;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpHeaders;
import org.springframework.http.ResponseCookie;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RestController;
import java.time.Duration;
import java.time.Instant;
import java.util.Locale;

@RestController
@RequiredArgsConstructor
@Tag(name = "认证", description = "用户登录、注册、令牌刷新")
public class AuthController {
    private static final String CLIENT_PLATFORM_HEADER = "X-Client-Platform";
    private static final String DEVICE_ID_HEADER = "X-Device-Id";
    private static final String DEVICE_NAME_HEADER = "X-Device-Name";
    private static final String REFRESH_COOKIE_NAME = "omninest_refresh_token";

    private final AuthService authService;
    private final BrowserSecurityPolicy browserSecurityPolicy;
    private final RateLimitService rateLimitService;
    private final RegistrationPolicy registrationPolicy;
    private final ClientIpResolver clientIpResolver;

    @Operation(summary = "用户注册", description = "新用户注册并返回访问令牌和刷新令牌，按 IP 限流")
    @PostMapping("/api/v1/auth/register")
    ApiResponse<AuthTokenResponse> register(
            @Valid @RequestBody RegisterRequest request,
            @RequestHeader(name = CLIENT_PLATFORM_HEADER, required = false, defaultValue = "native") String clientPlatform,
            @RequestHeader(name = DEVICE_ID_HEADER, required = false) String deviceId,
            @RequestHeader(name = DEVICE_NAME_HEADER, required = false) String deviceName,
            HttpServletRequest httpRequest,
            HttpServletResponse response
    ) {
        registrationPolicy.requireRegistrationEnabled();
        String ip = resolveClientIp(httpRequest);
        if (!rateLimitService.tryAcquire("ip:" + ip + ":register", 3, Duration.ofHours(1))) {
            throw new BusinessException(ErrorCode.RATE_LIMITED, "注册请求过于频繁，请稍后再试");
        }
        return issueResponse(
                authService.register(request, clientPlatform, deviceId, deviceName, ip,
                        httpRequest.getHeader("User-Agent")),
                clientPlatform,
                response
        );
    }

    @Operation(summary = "用户登录", description = "用户名密码登录，支持按 IP 和用户名双重限流；已开启两步验证时返回挑战令牌")
    @PostMapping("/api/v1/auth/login")
    ApiResponse<AuthTokenResponse> login(
            @Valid @RequestBody LoginRequest request,
            @RequestHeader(name = CLIENT_PLATFORM_HEADER, required = false, defaultValue = "native") String clientPlatform,
            @RequestHeader(name = DEVICE_ID_HEADER, required = false) String deviceId,
            @RequestHeader(name = DEVICE_NAME_HEADER, required = false) String deviceName,
            HttpServletRequest httpRequest,
            HttpServletResponse response
    ) {
        String ip = resolveClientIp(httpRequest);
        // 按 IP 限流
        if (!rateLimitService.tryAcquire("ip:" + ip + ":login", 10, Duration.ofMinutes(1))) {
            throw new BusinessException(ErrorCode.RATE_LIMITED, "登录请求过于频繁，请稍后再试");
        }
        // 按用户名限流
        if (!rateLimitService.tryAcquire("user:" + request.username() + ":login", 5, Duration.ofMinutes(1))) {
            throw new BusinessException(ErrorCode.RATE_LIMITED, "该账号登录尝试过多，请稍后再试");
        }
        AuthTokenResponse token = authService.login(request, clientPlatform, deviceId, deviceName, ip,
                httpRequest.getHeader("User-Agent"));
        if (Boolean.TRUE.equals(token.twoFactorRequired())) {
            return ApiResponse.success(token);
        }
        return issueResponse(token, clientPlatform, response);
    }

    @Operation(summary = "两步验证登录", description = "使用第一步登录返回的挑战令牌与验证码完成登录")
    @PostMapping("/api/v1/auth/login/2fa")
    ApiResponse<AuthTokenResponse> loginWithTwoFactor(
            @Valid @RequestBody TwoFactorLoginRequest request,
            @RequestHeader(name = CLIENT_PLATFORM_HEADER, required = false, defaultValue = "native") String clientPlatform,
            @RequestHeader(name = DEVICE_ID_HEADER, required = false) String deviceId,
            @RequestHeader(name = DEVICE_NAME_HEADER, required = false) String deviceName,
            HttpServletRequest httpRequest,
            HttpServletResponse response
    ) {
        String ip = resolveClientIp(httpRequest);
        if (!rateLimitService.tryAcquire("ip:" + ip + ":2fa", 10, Duration.ofMinutes(1))) {
            throw new BusinessException(ErrorCode.RATE_LIMITED, "两步验证请求过于频繁，请稍后再试");
        }
        return issueResponse(
                authService.completeTwoFactorLogin(
                        request.challengeToken(),
                        request.code(),
                        clientPlatform,
                        deviceId,
                        deviceName,
                        ip,
                        httpRequest.getHeader("User-Agent")
                ),
                clientPlatform,
                response
        );
    }

    @Operation(summary = "两步验证注册引导：生成秘钥", description = "强制角色首次登录未开启两步验证时，用注册挑战令牌生成 TOTP 秘钥")
    @PostMapping("/api/v1/auth/login/2fa/setup")
    ApiResponse<TwoFactorSetupResponse> bootstrapTwoFactorSetup(
            @Valid @RequestBody TwoFactorBootstrapSetupRequest request,
            HttpServletRequest httpRequest
    ) {
        String ip = resolveClientIp(httpRequest);
        if (!rateLimitService.tryAcquire("ip:" + ip + ":2fa", 10, Duration.ofMinutes(1))) {
            throw new BusinessException(ErrorCode.RATE_LIMITED, "两步验证请求过于频繁，请稍后再试");
        }
        return ApiResponse.success(authService.bootstrapTwoFactorSetup(request.challengeToken(), request.password()));
    }

    @Operation(summary = "两步验证注册引导：确认启用", description = "确认验证码启用两步验证，返回一次性备份码与完成令牌")
    @PostMapping("/api/v1/auth/login/2fa/enable")
    ApiResponse<TwoFactorBootstrapEnableResponse> bootstrapTwoFactorEnable(
            @Valid @RequestBody TwoFactorBootstrapEnableRequest request,
            HttpServletRequest httpRequest
    ) {
        String ip = resolveClientIp(httpRequest);
        if (!rateLimitService.tryAcquire("ip:" + ip + ":2fa", 10, Duration.ofMinutes(1))) {
            throw new BusinessException(ErrorCode.RATE_LIMITED, "两步验证请求过于频繁，请稍后再试");
        }
        return ApiResponse.success(authService.bootstrapTwoFactorEnable(request.challengeToken(), request.code()));
    }

    @Operation(summary = "两步验证注册引导：完成注册", description = "用户确认保存备份码后，用完成令牌换取登录令牌")
    @PostMapping("/api/v1/auth/login/2fa/complete")
    ApiResponse<AuthTokenResponse> completeTwoFactorEnrollment(
            @Valid @RequestBody TwoFactorFinalizeRequest request,
            @RequestHeader(name = CLIENT_PLATFORM_HEADER, required = false, defaultValue = "native") String clientPlatform,
            @RequestHeader(name = DEVICE_ID_HEADER, required = false) String deviceId,
            @RequestHeader(name = DEVICE_NAME_HEADER, required = false) String deviceName,
            HttpServletRequest httpRequest,
            HttpServletResponse response
    ) {
        String ip = resolveClientIp(httpRequest);
        if (!rateLimitService.tryAcquire("ip:" + ip + ":2fa", 10, Duration.ofMinutes(1))) {
            throw new BusinessException(ErrorCode.RATE_LIMITED, "两步验证请求过于频繁，请稍后再试");
        }
        return issueResponse(
                authService.completeTwoFactorEnrollment(
                        request.finalizeToken(),
                        clientPlatform,
                        deviceId,
                        deviceName,
                        ip,
                        httpRequest.getHeader("User-Agent")
                ),
                clientPlatform,
                response
        );
    }

    @Operation(summary = "刷新令牌", description = "使用刷新令牌获取新的访问令牌，支持 Web 端 HttpOnly Cookie 方式")
    @PostMapping("/api/v1/auth/refresh")
    ApiResponse<AuthTokenResponse> refresh(
            @RequestBody(required = false) RefreshRequest request,
            @RequestHeader(name = CLIENT_PLATFORM_HEADER, required = false, defaultValue = "native") String clientPlatform,
            HttpServletRequest httpRequest,
            HttpServletResponse response
    ) {
        String ip = resolveClientIp(httpRequest);
        if (!rateLimitService.tryAcquire("ip:" + ip + ":refresh", 30, Duration.ofMinutes(1))) {
            throw new BusinessException(ErrorCode.RATE_LIMITED, "刷新请求过于频繁");
        }
        String refreshToken = resolveRefreshToken(clientPlatform, request, httpRequest);
        return issueResponse(authService.refresh(refreshToken), clientPlatform, response);
    }

    @Operation(summary = "退出登录", description = "吊销当前刷新会话并清除刷新 Cookie；凭证无效时幂等成功")
    @PostMapping("/api/v1/auth/logout")
    ApiResponse<Void> logout(
            @RequestBody(required = false) RefreshRequest request,
            @RequestHeader(name = CLIENT_PLATFORM_HEADER, required = false, defaultValue = "native") String clientPlatform,
            HttpServletRequest httpRequest,
            HttpServletResponse response
    ) {
        String ip = resolveClientIp(httpRequest);
        if (!rateLimitService.tryAcquire("ip:" + ip + ":logout", 10, Duration.ofMinutes(1))) {
            throw new BusinessException(ErrorCode.RATE_LIMITED, "退出请求过于频繁，请稍后再试");
        }
        String refreshToken = resolveRefreshToken(clientPlatform, request, httpRequest);
        authService.logout(refreshToken);
        clearRefreshCookie(response);
        return ApiResponse.success(null);
    }

    private ApiResponse<AuthTokenResponse> issueResponse(
            AuthTokenResponse token,
            String clientPlatform,
            HttpServletResponse response
    ) {
        if (isWebClient(clientPlatform)) {
            writeRefreshCookie(response, token.refreshToken(), token.refreshExpiresAt());
            return ApiResponse.success(token.withoutRefreshToken());
        }
        return ApiResponse.success(token);
    }

    private boolean isWebClient(String clientPlatform) {
        return "web".equalsIgnoreCase(clientPlatform);
    }

    private String resolveRefreshToken(
            String clientPlatform,
            RefreshRequest request,
            HttpServletRequest httpRequest
    ) {
        if (isWebClient(clientPlatform)) {
            String cookieValue = readRefreshCookie(httpRequest);
            if (cookieValue != null && !cookieValue.isBlank()) {
                return cookieValue;
            }
        }
        if (request != null && request.refreshToken() != null && !request.refreshToken().isBlank()) {
            return request.refreshToken();
        }
        String cookieValue = readRefreshCookie(httpRequest);
        if (cookieValue != null && !cookieValue.isBlank()) {
            return cookieValue;
        }
        return null;
    }

    private String readRefreshCookie(HttpServletRequest request) {
        if (request.getCookies() == null) {
            return null;
        }
        for (var cookie : request.getCookies()) {
            if (REFRESH_COOKIE_NAME.equals(cookie.getName())) {
                return cookie.getValue();
            }
        }
        return null;
    }

    private void writeRefreshCookie(HttpServletResponse response, String refreshToken, String expiresAt) {
        if (refreshToken == null || refreshToken.isBlank()) {
            return;
        }
        ResponseCookie cookie = ResponseCookie.from(REFRESH_COOKIE_NAME, refreshToken)
                .httpOnly(true)
                .secure(refreshCookieSecure())
                .sameSite(refreshCookieSameSite())
                .path("/api/v1/auth")
                .maxAge(resolveMaxAge(expiresAt))
                .build();
        response.addHeader(HttpHeaders.SET_COOKIE, cookie.toString());
    }

    /**
     * SameSite 属性取安全策略配置并归一化：合法值为 Strict/Lax/None，
     * 缺省或非法值回落 Strict（测试桩的接口默认方法可能返回 null）。
     */
    private String refreshCookieSameSite() {
        String value = browserSecurityPolicy.refreshCookieSameSite();
        if (value == null || value.isBlank()) {
            return "Strict";
        }
        return switch (value.trim().toUpperCase(Locale.ROOT)) {
            case "LAX" -> "Lax";
            case "NONE" -> "None";
            default -> "Strict";
        };
    }

    /**
     * SameSite=None 不带 Secure 会被浏览器整体拒绝，该形态下强制安全传输。
     */
    private boolean refreshCookieSecure() {
        return "None".equals(refreshCookieSameSite()) || browserSecurityPolicy.refreshCookieSecure();
    }

    private Duration resolveMaxAge(String expiresAt) {
        try {
            return Duration.between(Instant.now(), Instant.parse(expiresAt));
        } catch (RuntimeException ex) {
            return Duration.ofDays(30);
        }
    }

    // 登出时以相同属性覆盖刷新 Cookie，使浏览器立即删除。
    private void clearRefreshCookie(HttpServletResponse response) {
        ResponseCookie cookie = ResponseCookie.from(REFRESH_COOKIE_NAME, "")
                .httpOnly(true)
                .secure(refreshCookieSecure())
                .sameSite(refreshCookieSameSite())
                .path("/api/v1/auth")
                .maxAge(Duration.ZERO)
                .build();
        response.addHeader(HttpHeaders.SET_COOKIE, cookie.toString());
    }

    private String resolveClientIp(HttpServletRequest request) {
        return clientIpResolver.resolve(
                request.getRemoteAddr(),
                request.getHeader("X-Forwarded-For"),
                request.getHeader("X-Real-IP")
        );
    }
}
