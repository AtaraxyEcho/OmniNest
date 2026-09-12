package com.omninest.modules.user.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/**
 * 首次安装时创建超级管理员的请求。
 *
 * @author OmniNest
 */
@Schema(description = "首次安装超级管理员请求")
public record InitialSetupRequest(
        @Schema(description = "用户名", example = "root")
        @NotBlank(message = "用户名不能为空")
        @Size(max = 80, message = "用户名长度不能超过 80 个字符")
        String username,
        @Schema(description = "展示名称", example = "超级管理员")
        @Size(max = 120, message = "展示名称长度不能超过 120 个字符")
        String displayName,
        @Schema(description = "邮箱", example = "root@example.com")
        @Email(message = "邮箱格式不正确")
        @Size(max = 255, message = "邮箱长度不能超过 255 个字符")
        String email,
        @Schema(description = "密码")
        @NotBlank(message = "密码不能为空")
        @Size(min = 8, max = 24, message = "密码长度必须在 8 到 24 个字符之间")
        String password,
        @Schema(description = "实例名称", example = "OmniNest")
        @Size(max = 120, message = "实例名称长度不能超过 120 个字符")
        String instanceName,
        @Schema(description = "默认语言", example = "zh-CN")
        @Size(max = 20, message = "默认语言长度不能超过 20 个字符")
        String defaultLocale,
        @Schema(description = "默认时区", example = "Asia/Shanghai")
        @Size(max = 64, message = "默认时区长度不能超过 64 个字符")
        String defaultTimezone,
        @Schema(description = "两步验证秘钥（安装向导要求两步验证时必填）")
        @Size(max = 64, message = "两步验证秘钥长度不合法")
        String totpSecret,
        @Schema(description = "两步验证确认码（安装向导要求两步验证时必填）")
        @Size(min = 6, max = 6, message = "两步验证码必须是 6 位")
        String totpCode
) {
}
