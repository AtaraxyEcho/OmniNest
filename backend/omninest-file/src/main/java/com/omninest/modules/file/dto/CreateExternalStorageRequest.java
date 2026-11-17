package com.omninest.modules.file.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotBlank;

@Schema(description = "创建外部存储请求")
public record CreateExternalStorageRequest(
        @Schema(description = "存储提供者", example = "RCLONE") @NotBlank String provider,
        @Schema(description = "显示名称", example = "我的网盘") @NotBlank String displayName,
        @Schema(description = "加密凭据") @NotBlank String encryptedCredentials
) {
}
