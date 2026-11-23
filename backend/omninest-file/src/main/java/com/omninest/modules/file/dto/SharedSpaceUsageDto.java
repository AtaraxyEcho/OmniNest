package com.omninest.modules.file.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import java.util.List;

@Schema(description = "共享空间使用情况")
public record SharedSpaceUsageDto(
        @Schema(description = "已使用字节数") long usedBytes,
        @Schema(description = "最大容量字节数") long maxBytes,
        @Schema(description = "文件数量") long fileCount,
        @Schema(description = "按文件类型分布统计") List<FileTypeStatsDto> typeDistribution
) {
    public SharedSpaceUsageDto(long usedBytes, long maxBytes, long fileCount) {
        this(usedBytes, maxBytes, fileCount, List.of());
    }
}
