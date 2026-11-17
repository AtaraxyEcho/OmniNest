package com.omninest.modules.user.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotBlank;

@Schema(description = "管理员更新用户状态请求")
public record AdminUpdateUserStatusRequest(
        @Schema(description = "用户状态", example = "ACTIVE", allowableValues = {"ACTIVE", "DISABLED"}) @NotBlank(message = "用户状态不能为空") String status
) {
}
