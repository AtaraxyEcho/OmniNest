package com.omninest.modules.user.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotBlank;
import java.util.List;

/**
 * 两步验证（TOTP）相关请求与响应 DTO。
 *
 * @author OmniNest
 */
public final class TwoFactorDtos {

    private TwoFactorDtos() {
    }

    /** 自助开启：生成秘钥请求。 */
    @Schema(description = "两步验证生成秘钥请求")
    public record TwoFactorSetupRequest(
            @Schema(description = "登录密码", example = "secret123") @NotBlank(message = "密码不能为空") String password
    ) {
    }

    /** 自助/引导：确认启用请求。 */
    @Schema(description = "两步验证确认启用请求")
    public record TwoFactorEnableRequest(
            @Schema(description = "认证器当前 6 位验证码", example = "123456") @NotBlank(message = "验证码不能为空") String code
    ) {
    }

    /** 关闭两步验证请求。 */
    @Schema(description = "两步验证关闭请求")
    public record TwoFactorDisableRequest(
            @Schema(description = "登录密码", example = "secret123") @NotBlank(message = "密码不能为空") String password
    ) {
    }

    /** 两步验证登录第二步请求。 */
    @Schema(description = "两步验证登录请求")
    public record TwoFactorLoginRequest(
            @Schema(description = "第一步登录返回的挑战令牌") @NotBlank(message = "挑战令牌不能为空") String challengeToken,
            @Schema(description = "6 位验证码或备份码", example = "123456") @NotBlank(message = "验证码不能为空") String code
    ) {
    }

    /** 强制角色注册引导：生成秘钥请求。 */
    @Schema(description = "两步验证注册引导生成秘钥请求")
    public record TwoFactorBootstrapSetupRequest(
            @Schema(description = "注册引导挑战令牌") @NotBlank(message = "挑战令牌不能为空") String challengeToken,
            @Schema(description = "登录密码", example = "secret123") @NotBlank(message = "密码不能为空") String password
    ) {
    }

    /** 强制角色注册引导：确认启用请求。 */
    @Schema(description = "两步验证注册引导确认启用请求")
    public record TwoFactorBootstrapEnableRequest(
            @Schema(description = "注册引导挑战令牌") @NotBlank(message = "挑战令牌不能为空") String challengeToken,
            @Schema(description = "认证器当前 6 位验证码", example = "123456") @NotBlank(message = "验证码不能为空") String code
    ) {
    }

    /** 强制角色注册引导：完成注册请求。 */
    @Schema(description = "两步验证注册引导完成请求")
    public record TwoFactorFinalizeRequest(
            @Schema(description = "确认启用返回的完成令牌") @NotBlank(message = "完成令牌不能为空") String finalizeToken
    ) {
    }

    /** 秘钥与扫码 URI。 */
    @Schema(description = "两步验证秘钥响应")
    public record TwoFactorSetupResponse(
            @Schema(description = "Base32 秘钥") String secret,
            @Schema(description = "认证器扫码 URI") String otpauthUri
    ) {
    }

    /** 自助启用结果：一次性备份码。 */
    @Schema(description = "两步验证启用结果")
    public record TwoFactorEnableResponse(
            @Schema(description = "一次性明文备份码，仅此一次返回") List<String> backupCodes
    ) {
    }

    /** 引导启用结果：备份码与完成令牌。 */
    @Schema(description = "两步验证注册引导启用结果")
    public record TwoFactorBootstrapEnableResponse(
            @Schema(description = "一次性明文备份码，仅此一次返回") List<String> backupCodes,
            @Schema(description = "用户确认保存备份码后用于换取登录令牌") String finalizeToken
    ) {
    }

    /** 两步验证状态。 */
    @Schema(description = "两步验证状态")
    public record TwoFactorStatusResponse(
            @Schema(description = "是否已开启") boolean enabled,
            @Schema(description = "当前角色是否被策略强制要求开启") boolean required
    ) {
    }
}
