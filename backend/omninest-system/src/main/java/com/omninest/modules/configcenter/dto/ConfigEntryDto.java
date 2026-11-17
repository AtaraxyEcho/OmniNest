package com.omninest.modules.configcenter.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import java.time.Instant;
import java.util.List;

@Schema(description = "配置中心条目")
public record ConfigEntryDto(
        @Schema(description = "配置键", example = "app.upload.max-size") String key,
        @Schema(description = "配置值", example = "104857600") String value,
        @Schema(description = "值类型", example = "LONG") String valueType,
        @Schema(description = "配置分类", example = "upload") String category,
        @Schema(description = "刷新范围", example = "HOT") String refreshScope,
        @Schema(description = "更新时间") Instant updatedAt,
        @Schema(description = "配置描述") String description,
        @Schema(description = "管理界面归属", example = "GENERAL") String surface,
        @Schema(description = "前端本地化编码") String displayCode,
        @Schema(description = "是否允许编辑") boolean editable,
        @Schema(description = "敏感值是否已配置") boolean sensitiveConfigured,
        @Schema(description = "允许的枚举值") List<String> allowedValues
) {
    public ConfigEntryDto(
            String key,
            String value,
            String valueType,
            String category,
            String refreshScope,
            Instant updatedAt,
            String description
    ) {
        this(
                key, value, valueType, category, refreshScope, updatedAt, description,
                "GENERAL", key, true, false, List.of()
        );
    }
}
