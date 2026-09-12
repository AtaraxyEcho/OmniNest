package com.omninest.modules.user.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

@Schema(description = "用户注册请求")
public record RegisterRequest(
        @Schema(description = "用户名", example = "newuser") @NotBlank(message = "用户名不能为空") @Size(max = 80, message = "用户名长度不能超过 80 个字符") String username,
        @Schema(description = "展示名称", example = "新用户") @Size(max = 120, message = "展示名称长度不能超过 120 个字符") String displayName,
        @Schema(description = "邮箱", example = "user@example.com") @Email(message = "邮箱格式不正确") @Size(max = 255, message = "邮箱长度不能超过 255 个字符") String email,
        @Schema(description = "密码", example = "password123") @NotBlank(message = "密码不能为空") @Size(min = 8, max = 24, message = "密码长度必须在 8 到 24 个字符之间") String password
) {
}
