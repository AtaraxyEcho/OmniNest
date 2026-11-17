package com.omninest.modules.file.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import java.util.UUID;

/**
 * 文件永久删除任务响应。
 *
 * @param taskId 任务 ID
 * @param status 任务状态
 * @param phase 执行阶段
 * @author OmniNest
 */
@Schema(description = "文件永久删除任务")
public record FilePurgeTaskDto(
        @Schema(description = "任务 ID") UUID taskId,
        @Schema(description = "任务状态", example = "QUEUED") String status,
        @Schema(description = "执行阶段", example = "PLANNING") String phase
) {
    /**
     * 创建排队响应。
     *
     * @param taskId 任务 ID
     * @return 排队响应
     */
    public static FilePurgeTaskDto queued(UUID taskId) {
        return new FilePurgeTaskDto(taskId, "QUEUED", "PLANNING");
    }
}
