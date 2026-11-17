package com.omninest.modules.file.dto;

import io.swagger.v3.oas.annotations.media.Schema;

@Schema(description = "文件类型统计")
public record FileTypeStatsDto(
        @Schema(description = "文件类型分类", example = "DOCUMENT") String category,
        @Schema(description = "文件数量", example = "100") long count,
        @Schema(description = "总大小（字节）", example = "1073741824") long sizeBytes
) {
}
