package com.omninest.modules.file.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import java.time.Instant;
import java.util.UUID;

@Schema(description = "文件下载链接信息")
public record FileDownloadUrlDto(
        @Schema(description = "文件 ID") UUID fileId,
        @Schema(description = "文件名", example = "文档.pdf") String fileName,
        @Schema(description = "下载链接") String downloadUrl,
        @Schema(description = "链接过期时间") Instant expiresAt
) {
}
