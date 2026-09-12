package com.omninest.modules.user.controller;

import com.omninest.common.api.ApiResponse;
import com.omninest.common.security.CurrentUserContext;
import com.omninest.modules.user.dto.TwoFactorDtos.TwoFactorDisableRequest;
import com.omninest.modules.user.dto.TwoFactorDtos.TwoFactorEnableRequest;
import com.omninest.modules.user.dto.TwoFactorDtos.TwoFactorEnableResponse;
import com.omninest.modules.user.dto.TwoFactorDtos.TwoFactorSetupRequest;
import com.omninest.modules.user.dto.TwoFactorDtos.TwoFactorSetupResponse;
import com.omninest.modules.user.dto.TwoFactorDtos.TwoFactorStatusResponse;
import com.omninest.modules.user.repository.AuthUserRepository;
import com.omninest.modules.user.service.TwoFactorPolicyService;
import com.omninest.modules.user.service.TwoFactorService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
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

    private final TwoFactorService twoFactorService;
    private final TwoFactorPolicyService twoFactorPolicyService;
    private final AuthUserRepository authUserRepository;
    private final CurrentUserContext currentUserContext;

    @Operation(summary = "两步验证状态", description = "返回当前用户是否已开启以及策略是否强制要求开启")
    @GetMapping("/api/v1/me/2fa/status")
    ApiResponse<TwoFactorStatusResponse> status() {
        UUID userId = currentUserContext.requireCurrentUserId();
        boolean enabled = twoFactorService.isEnabled(userId);
        boolean required = authUserRepository.findWithRolesById(userId)
                .map(twoFactorPolicyService::isRequired)
                .orElse(false);
        return ApiResponse.success(new TwoFactorStatusResponse(enabled, required));
    }

    @Operation(summary = "生成两步验证秘钥", description = "密码复核后生成 TOTP 秘钥与扫码 URI，重复调用覆盖未确认秘钥")
    @PostMapping("/api/v1/me/2fa/setup")
    ApiResponse<TwoFactorSetupResponse> setup(@Valid @RequestBody TwoFactorSetupRequest request) {
        UUID userId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(twoFactorService.startSetup(userId, request.password()));
    }

    @Operation(summary = "确认开启两步验证", description = "校验认证器验证码后启用，返回一次性备份码")
    @PostMapping("/api/v1/me/2fa/enable")
    ApiResponse<TwoFactorEnableResponse> enable(@Valid @RequestBody TwoFactorEnableRequest request) {
        UUID userId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(new TwoFactorEnableResponse(twoFactorService.enable(userId, request.code())));
    }

    @Operation(summary = "关闭两步验证", description = "密码复核后关闭并清除全部凭据与备份码")
    @PostMapping("/api/v1/me/2fa/disable")
    ApiResponse<Void> disable(@Valid @RequestBody TwoFactorDisableRequest request) {
        UUID userId = currentUserContext.requireCurrentUserId();
        twoFactorService.disable(userId, request.password());
        return ApiResponse.success();
    }
}
