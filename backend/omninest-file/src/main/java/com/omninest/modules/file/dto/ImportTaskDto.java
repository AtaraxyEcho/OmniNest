package com.omninest.modules.file.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import java.time.Instant;
import java.util.UUID;

/**
 * 外部存储导入任务信息。
 *
 * @author OmniNest
 */
@Schema(description = "外部存储导入任务信息")
public record ImportTaskDto(
        @Schema(description = "任务 ID") UUID id,
        @Schema(description = "系统任务 ID") UUID taskId,
        @Schema(description = "外部存储账户 ID") UUID externalAccountId,
        @Schema(description = "源路径", example = "/photos/vacation") String sourcePath,
        @Schema(description = "导入源类型：FILE 或 DIRECTORY") String sourceKind,
        @Schema(description = "文件名", example = "photo.jpg") String fileName,
        @Schema(description = "文件总大小（字节）", example = "1048576") long totalBytes,
        @Schema(description = "已传输大小（字节）", example = "1048576") long transferredBytes,
        @Schema(description = "传输速度（字节/秒）", example = "1048576") long speedBytes,
        @Schema(description = "文件总数") int totalFiles,
        @Schema(description = "已完成文件数") int completedFiles,
        @Schema(description = "当前处理文件") String currentFileName,
        @Schema(description = "任务状态", example = "COMPLETED") String status,
        @Schema(description = "错误摘要") String errorSummary,
        @Schema(description = "完成后生成的文件 ID") UUID completedFileId,
        @Schema(description = "创建时间") Instant createdAt,
        @Schema(description = "更新时间") Instant updatedAt
) {
}
