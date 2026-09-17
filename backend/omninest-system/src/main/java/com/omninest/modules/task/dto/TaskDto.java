package com.omninest.modules.task.dto;

import com.omninest.modules.task.domain.TaskRecord;
import io.swagger.v3.oas.annotations.media.Schema;
import java.time.Instant;
import java.util.UUID;

/**
 * 任务数据传输对象。
 *
 * <p>本人任务接口默认不返回失败堆栈摘要；管理端诊断请使用含
 * {@link #from(TaskRecord, boolean)} 的显式调用。</p>
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
        @Schema(description = "失败堆栈摘要，脱敏截断；本人任务默认不返回") String stackSummary,
        @Schema(description = "完成结果 JSON，供调用方读取晋升产物标识") String result,
        @Schema(description = "更新时间") Instant updatedAt
) {

    /**
     * 从实体转换为本人可见 DTO，不包含堆栈摘要。
     */
    public static TaskDto from(TaskRecord record) {
        return from(record, false);
    }

    /**
     * 从实体转换为 DTO。
     *
     * @param record 任务记录
     * @param includeDiagnostics 是否包含失败堆栈摘要等诊断字段
     */
    public static TaskDto from(TaskRecord record, boolean includeDiagnostics) {
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
                includeDiagnostics ? record.getStackSummary() : null,
                record.getResult(),
                record.getUpdatedAt()
        );
    }
}
