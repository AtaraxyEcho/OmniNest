package com.omninest.modules.notification.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import java.time.Instant;
import java.util.Map;
import java.util.UUID;

@Schema(description = "通知信息")
public record NotificationDto(
        @Schema(description = "通知 ID") UUID id,
        @Schema(description = "通知类型", example = "TASK_COMPLETED") String type,
        @Schema(description = "通知标题", example = "任务完成") String title,
        @Schema(description = "通知内容") String message,
        @Schema(description = "是否已读", example = "false") boolean read,
        @Schema(description = "创建时间") Instant createdAt,
        @Schema(description = "业务元数据（taskId、shareId 等跳转上下文）") Map<String, Object> metadata
) {

    public NotificationDto(
            UUID id,
            String type,
            String title,
            String message,
            boolean read,
            Instant createdAt
    ) {
        this(id, type, title, message, read, createdAt, Map.of());
    }
}
