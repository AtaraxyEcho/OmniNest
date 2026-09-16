package com.omninest.modules.task.dto;

import com.omninest.modules.task.domain.TaskRecord;
import io.swagger.v3.oas.annotations.media.Schema;
import java.time.Instant;
import java.util.UUID;

/**
 * 任务数据传输对象
 */
@Schema(description = "任务信息")
public record TaskDto(
        @Schema(description = "任务 ID") UUID id,
        @Schema(description = "任务类型", example = "FILE_INDEX") String type,
        @Schema(description = "任务状态", example = "COMPLETED") String status,
        @Schema(description = "任务执行阶段", example = "DELETING_OBJECTS") String phase,
        @Schema(description = "进度百分比", example = "100") int progress,
        @Schema(description = "关联资源类型", example = "FILE_NODE") String resourceType,
        @Schema(description = "关联资源 ID") UUID resourceId,
        @Schema(description = "已重试次数", example = "0") int retryCount,
        @Schema(description = "错误摘要") String errorSummary,
        @Schema(description = "失败堆栈摘要，脱敏截断") String stackSummary,
        @Schema(description = "更新时间") Instant updatedAt
) {

    /**
     * 从实体转换为 DTO
     */
    public static TaskDto from(TaskRecord record) {
        return new TaskDto(
                record.getId(),
                record.getTaskType(),
                record.getStatus(),
                record.getPhase(),
                record.getProgress(),
                record.getResourceType(),
                record.getResourceId(),
                record.getRetryCount(),
                record.getErrorMessage(),
                record.getStackSummary(),
                record.getUpdatedAt()
        );
    }
}
