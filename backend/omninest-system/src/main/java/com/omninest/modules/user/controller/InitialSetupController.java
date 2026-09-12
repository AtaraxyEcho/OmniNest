package com.omninest.modules.user.controller;

import com.omninest.common.api.ApiResponse;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.ratelimit.RateLimitService;
import com.omninest.modules.user.dto.InitialSetupRequest;
import com.omninest.modules.user.dto.InitialSetupResultDto;
import com.omninest.modules.user.dto.InitialSetupStatusDto;
import com.omninest.modules.user.dto.TwoFactorDtos.TwoFactorSetupResponse;
import com.omninest.modules.user.service.InitialSetupService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import java.time.Duration;
import java.util.Map;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RestController;

/**
 * 首次安装向导接口。
 *
 * @author OmniNest
 */
@RestController
@RequiredArgsConstructor
@Tag(name = "首次安装", description = "查询安装状态并创建首个超级管理员")
public class InitialSetupController {
    private static final String SETUP_TOKEN_HEADER = "X-Setup-Token";

    private final InitialSetupService initialSetupService;
    private final RateLimitService rateLimitService;

    /**
     * 查询首次安装状态。
     *
     * @return 首次安装状态
     */
    @Operation(summary = "查询首次安装状态")
    @GetMapping("/api/v1/setup/status")
    ApiResponse<InitialSetupStatusDto> status() {
        return ApiResponse.success(initialSetupService.status());
    }

    /**
     * 生成安装向导两步验证秘钥（仅安装未完成时可用）。
     *
     * @param body 含超管用户名的请求体
     * @param servletRequest HTTP 请求
     * @return 秘钥与扫码 URI
     */
    @Operation(summary = "安装向导生成两步验证秘钥", description = "仅在首次安装未完成时可用，返回 Base32 秘钥与 otpauth URI")
    @PostMapping("/api/v1/setup/2fa/secret")
    ApiResponse<TwoFactorSetupResponse> newTwoFactorSecret(
            @RequestBody(required = false) Map<String, String> body,
            HttpServletRequest servletRequest
    ) {
        String remoteAddress = servletRequest.getRemoteAddr();
        if (!rateLimitService.tryAcquire(
                "setup:2fa:ip:" + remoteAddress,
                10,
                Duration.ofMinutes(15)
        )) {
            throw new BusinessException(ErrorCode.RATE_LIMITED, "秘钥生成请求过于频繁，请稍后再试");
        }
        return ApiResponse.success(
                initialSetupService.newTwoFactorSecret(body == null ? null : body.get("username"))
        );
    }

    /**
     * 创建首个超级管理员。
     *
     * @param setupToken 安装令牌
     * @param request 超级管理员资料
     * @param servletRequest HTTP 请求
     * @return 启用两步验证时返回一次性备份码
     */
    @Operation(summary = "创建首个超级管理员", description = "按部署姿态要求完成两步验证注册，启用时返回一次性备份码")
    @PostMapping("/api/v1/setup/super-admin")
    ApiResponse<InitialSetupResultDto> createSuperAdmin(
            @RequestHeader(name = SETUP_TOKEN_HEADER, required = false) String setupToken,
            @Valid @RequestBody InitialSetupRequest request,
            HttpServletRequest servletRequest
    ) {
        String remoteAddress = servletRequest.getRemoteAddr();
        if (!rateLimitService.tryAcquire(
                "setup:ip:" + remoteAddress,
                5,
                Duration.ofMinutes(15)
        ) || !rateLimitService.tryAcquire("setup:global", 30, Duration.ofMinutes(15))) {
            throw new BusinessException(ErrorCode.RATE_LIMITED, "安装请求过于频繁，请稍后再试");
        }
        return ApiResponse.success(
                new InitialSetupResultDto(initialSetupService.createSuperAdmin(setupToken, request))
        );
    }
}
