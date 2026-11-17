package com.omninest.modules.file.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotBlank;

/**
 * 远程路径操作请求。
 */
@Schema(description = "远程路径操作请求")
public record RemotePathRequest(
        @Schema(description = "远程路径", example = "/photos") @NotBlank(message = "远程路径不能为空") String remotePath
) {
}
