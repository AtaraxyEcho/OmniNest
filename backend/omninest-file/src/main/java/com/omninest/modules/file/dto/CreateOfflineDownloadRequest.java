package com.omninest.modules.file.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotBlank;
import java.util.UUID;

@Schema(description = "创建离线下载任务请求")
public record CreateOfflineDownloadRequest(
        @Schema(description = "下载源 URI", example = "https://example.com/file.zip") @NotBlank String sourceUri,
        @Schema(description = "目标文件夹 ID，null 表示下载到根目录") UUID targetParentId,
        @Schema(description = "空间类型：PERSONAL 或 SHARED，默认 PERSONAL") String spaceType
) {
}
