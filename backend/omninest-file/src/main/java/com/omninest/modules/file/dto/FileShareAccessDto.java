package com.omninest.modules.file.dto;

import io.swagger.v3.oas.annotations.media.Schema;

@Schema(description = "分享文件访问信息")
public record FileShareAccessDto(
        @Schema(description = "文件名", example = "文档.pdf") String fileName,
        @Schema(description = "MIME 类型", example = "application/pdf") String mimeType,
        @Schema(description = "文件大小（字节）", example = "1048576") long sizeBytes,
        @Schema(description = "下载链接") String downloadUrl,
        @Schema(description = "资源类型", example = "FILE") String resourceType
) {
}
