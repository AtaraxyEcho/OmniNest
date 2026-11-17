package com.omninest.modules.task.dto;

import io.swagger.v3.oas.annotations.media.Schema;

/**
 * 本人任务轻量摘要，供 Portal 角标使用；不包含堆栈与完整任务列表。
 */
@Schema(description = "本人任务摘要")
public record TaskSummaryDto(
        @Schema(description = "进行中任务数") long activeCount,
        @Schema(description = "失败任务数") long failedCount,
        @Schema(description = "优先展示任务（失败优先，其次运行中）") TaskDto priorityTask
) {
}
