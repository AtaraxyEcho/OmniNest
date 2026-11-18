package com.omninest.modules.user.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

@Schema(description = "管理员更新用户基础资料请求")
public record AdminUpdateUserProfileRequest(
        @Schema(description = "展示名称", example = "新用户")
        @NotBlank(message = "展示名称不能为空")
        @Size(max = 120, message = "展示名称长度不能超过 120 个字符")
        String displayName,
        @Schema(description = "邮箱；空字符串表示清除邮箱", example = "user@example.com")
        @Email(message = "邮箱格式不正确")
        @Size(max = 255, message = "邮箱长度不能超过 255 个字符")
        String email,
        @Schema(description = "是否要求用户首次登录后修改密码") Boolean requirePasswordChange
) {
    public AdminUpdateUserProfileRequest(String displayName, String email) {
        this(displayName, email, null);
    }
}
