package com.omninest.modules.file.dto;

import io.swagger.v3.oas.annotations.media.Schema;

/**
 * 外部存储空间使用情况。
 */
@Schema(description = "外部存储空间使用情况")
public record ExternalSpaceDto(
        @Schema(description = "总空间（字节）", example = "107374182400") long totalBytes,
        @Schema(description = "已用空间（字节）", example = "53687091200") long usedBytes,
        @Schema(description = "可用空间（字节）", example = "53687091200") long freeBytes,
        @Schema(description = "回收站占用（字节）", example = "1073741824") long trashedBytes
) {
}
