package com.omninest.modules.file.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import java.util.UUID;

/**
 * 文件节点对应的后台媒体导入任务。
 *
 * @param fileNodeId 文件节点 ID
 * @param taskId 任务 ID
 */
@Schema(description = "文件节点对应的后台媒体导入任务")
public record MediaImportTaskDto(
        @Schema(description = "文件节点 ID") UUID fileNodeId,
        @Schema(description = "后台任务 ID") UUID taskId
) {
}
