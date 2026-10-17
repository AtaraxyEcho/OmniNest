package com.omninest.modules.user.controller;

import com.omninest.common.api.ApiResponse;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.ratelimit.RateLimitService;
import com.omninest.common.security.CurrentUserContext;
import com.omninest.common.security.Permissions;
import com.omninest.modules.user.dto.TwoFactorDtos.TwoFactorDisableRequest;
import com.omninest.modules.user.dto.TwoFactorDtos.TwoFactorEnableRequest;
import com.omninest.modules.user.dto.TwoFactorDtos.TwoFactorEnableResponse;
import com.omninest.modules.user.dto.TwoFactorDtos.TwoFactorSetupRequest;
import com.omninest.modules.user.dto.TwoFactorDtos.TwoFactorSetupResponse;
import com.omninest.modules.user.dto.TwoFactorDtos.TwoFactorStatusResponse;
import com.omninest.modules.user.service.TwoFactorPolicyService;
import com.omninest.modules.user.service.TwoFactorService;
import com.omninest.modules.user.service.UserSessionRevocationService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import java.time.Duration;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

/**
 * 两步验证自助管理接口，路径挂在 /me 下以复用访问令牌鉴权（/auth/** 为公开前缀）。
 *
 * @author OmniNest
 */
@RestController
@RequiredArgsConstructor
@Tag(name = "两步验证", description = "TOTP 两步验证自助开启、确认与关闭")
public class TwoFactorController {

    /**
     * 与 {@code AuthService} 的注册引导流程共用同一份按用户计的频率预算，
     * 避免攻击者切换自助与引导两个入口叠加可用次数。
     */
    private static final Duration SETUP_WINDOW = Duration.ofHours(1);
    private static final Duration CODE_WINDOW = Duration.ofMinutes(1);

    private final TwoFactorService twoFactorService;
    private final TwoFactorPolicyService twoFactorPolicyService;
    private final CurrentUserContext currentUserContext;
    private final RateLimitService rateLimitService;
    private final UserSessionRevocationService userSessionRevocationService;

    @Operation(summary = "两步验证状态", description = "返回当前用户是否已开启以及策略是否强制要求开启")
    @GetMapping("/api/v1/me/2fa/status")
    @PreAuthorize("hasAuthority('" + Permissions.PROFILE_READ + "')")
    ApiResponse<TwoFactorStatusResponse> status() {
        UUID userId = currentUserContext.requireCurrentUserId();
        boolean enabled = twoFactorService.isEnabled(userId);
        boolean required = twoFactorPolicyService.isRequired(userId);
        return ApiResponse.success(new TwoFactorStatusResponse(enabled, required));
    }

    @Operation(summary = "生成两步验证秘钥", description = "密码复核后生成 TOTP 秘钥与扫码 URI，重复调用覆盖未确认秘钥")
    @PostMapping("/api/v1/me/2fa/setup")
    @PreAuthorize("hasAuthority('" + Permissions.PROFILE_WRITE + "')")
    ApiResponse<TwoFactorSetupResponse> setup(@Valid @RequestBody TwoFactorSetupRequest request) {
        UUID userId = currentUserContext.requireCurrentUserId();
        requireAttemptBudget(userId, "2fa-setup", 3, SETUP_WINDOW);
        return ApiResponse.success(twoFactorService.startSetup(userId, request.password()));
    }

    @Operation(summary = "确认开启两步验证", description = "校验认证器验证码后启用，返回一次性备份码")
    @PostMapping("/api/v1/me/2fa/enable")
    @PreAuthorize("hasAuthority('" + Permissions.PROFILE_WRITE + "')")
    ApiResponse<TwoFactorEnableResponse> enable(@Valid @RequestBody TwoFactorEnableRequest request) {
        UUID userId = currentUserContext.requireCurrentUserId();
        requireAttemptBudget(userId, "2fa-enable", 5, CODE_WINDOW);
        return ApiResponse.success(new TwoFactorEnableResponse(twoFactorService.enable(userId, request.code())));
    }

    @Operation(summary = "关闭两步验证", description = "密码与验证码复核后关闭并清除全部凭据与备份码；角色被策略强制时禁止关闭")
    @PostMapping("/api/v1/me/2fa/disable")
    @PreAuthorize("hasAuthority('" + Permissions.PROFILE_WRITE + "')")
    ApiResponse<Void> disable(@Valid @RequestBody TwoFactorDisableRequest request) {
        UUID userId = currentUserContext.requireCurrentUserId();
        if (twoFactorPolicyService.isRequired(userId)) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "当前角色受安全策略强制要求两步验证，不能自行关闭");
        }
        requireAttemptBudget(userId, "2fa-disable", 3, SETUP_WINDOW);
        twoFactorService.disable(userId, request.password(), request.code());
        // 关闭凭据后其他设备上的会话不能再被两步验证保护，一律吊销，仅保留当前会话
        userSessionRevocationService.revokeAllExcept(
                userId, currentUserContext.currentSessionId(), "TWO_FACTOR_DISABLED");
        return ApiResponse.success();
    }

    private void requireAttemptBudget(UUID userId, String action, int limit, Duration window) {
        if (!rateLimitService.tryAcquire("user:" + userId + ":" + action, limit, window)) {
            throw new BusinessException(ErrorCode.RATE_LIMITED, "两步验证操作过于频繁，请稍后再试");
        }
    }
}
