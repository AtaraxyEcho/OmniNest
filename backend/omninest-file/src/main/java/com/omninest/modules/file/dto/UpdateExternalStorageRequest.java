package com.omninest.modules.file.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotBlank;

@Schema(description = "更新外部存储请求")
public record UpdateExternalStorageRequest(
        @Schema(description = "显示名称", example = "我的网盘") @NotBlank String displayName,
        @Schema(description = "加密凭据") @NotBlank String encryptedCredentials
) {
}
