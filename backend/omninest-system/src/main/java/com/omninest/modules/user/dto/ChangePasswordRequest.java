package com.omninest.modules.user.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/**
 * 修改密码请求。
 */
@Schema(description = "修改密码请求")
public record ChangePasswordRequest(
        @Schema(description = "旧密码", example = "oldPass123") @NotBlank(message = "旧密码不能为空") String oldPassword,
        @Schema(description = "新密码", example = "newPass456")
        @NotBlank(message = "新密码不能为空")
        @Size(min = 8, max = 24, message = "密码长度必须在 8 到 24 个字符之间")
        String newPassword
) {}
