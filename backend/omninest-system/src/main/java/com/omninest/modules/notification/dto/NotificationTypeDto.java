package com.omninest.modules.notification.dto;

import com.omninest.modules.notification.domain.NotificationType;
import io.swagger.v3.oas.annotations.media.Schema;
import java.util.UUID;

/**
 * 通知类型配置 DTO。
 */
@Schema(description = "通知类型配置")
public record NotificationTypeDto(
        @Schema(description = "类型 ID") UUID id,
        @Schema(description = "类型编码", example = "TASK_COMPLETED") String typeCode,
        @Schema(description = "显示标签", example = "任务完成") String label,
        @Schema(description = "类型描述") String description,
        @Schema(description = "图标名称", example = "check-circle") String icon,
        @Schema(description = "颜色值", example = "#4CAF50") String color,
        @Schema(description = "排序序号", example = "1") int sortOrder,
        @Schema(description = "是否启用", example = "true") boolean enabled
) {
    /**
     * 从实体转换。
     */
    public static NotificationTypeDto from(NotificationType entity) {
        return new NotificationTypeDto(
                entity.getId(),
                entity.getTypeCode(),
                entity.getLabel(),
                entity.getDescription(),
                entity.getIcon(),
                entity.getColor(),
                entity.getSortOrder(),
                entity.isEnabled()
        );
    }
}
