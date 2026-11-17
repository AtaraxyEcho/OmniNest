package com.omninest.modules.file.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import java.util.List;

@Schema(description = "文件存储统计信息")
public record FileStorageStatsDto(
        @Schema(description = "文件总数", example = "5000") int totalFiles,
        @Schema(description = "文件夹总数", example = "200") int totalFolders,
        @Schema(description = "已用存储（字节）", example = "10737418240") long usedBytes,
        @Schema(description = "存储配额（字节）", example = "107374182400") long quotaBytes,
        @Schema(description = "配额状态", example = "NORMAL") String quotaStatus,
        @Schema(description = "文件类型分布") List<FileTypeStatsDto> typeDistribution
) {
}
