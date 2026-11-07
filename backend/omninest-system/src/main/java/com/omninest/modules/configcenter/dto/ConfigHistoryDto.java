package com.omninest.modules.configcenter.dto;

import com.omninest.modules.configcenter.domain.ConfigHistory;
import io.swagger.v3.oas.annotations.media.Schema;
import java.time.Instant;
import java.util.UUID;

/**
 * 配置变更历史 DTO。
 */
@Schema(description = "配置变更历史")
public record ConfigHistoryDto(
        @Schema(description = "记录 ID") UUID id,
        @Schema(description = "配置键", example = "app.upload.max-size") String configKey,
        @Schema(description = "旧值") String oldValue,
        @Schema(description = "新值") String newValue,
        @Schema(description = "变更者用户 ID") UUID changedBy,
        @Schema(description = "变更原因") String changeReason,
        @Schema(description = "创建时间") Instant createdAt
) {
    /** 敏感值掩码常量，审计与展示侧统一复用 */
    public static final String MASK = "******";

    /**
     * 从 ConfigHistory 实体转换为 DTO（不掩码）。
     *
     * @param history 历史记录实体
     * @return DTO 实例
     */
    public static ConfigHistoryDto from(ConfigHistory history) {
        return from(history, false);
    }

    /**
     * 从 ConfigHistory 实体转换为 DTO，支持敏感值掩码。
     *
     * <p>只掩码真正有内容的敏感值：{@code null} 表示「该项当时不存在」，空串表示
     * 「管理员把它清空了」。两者都按 {@code MASK} 呈现会让审计记录无法区分
     * 「设置了新密钥」与「撤销了密钥」，而空串本身不泄露任何信息。</p>
     *
     * @param history   历史记录实体
     * @param sensitive 是否为敏感配置项，若为 true 则掩码非空的 oldValue 和 newValue
     * @return DTO 实例
     */
    public static ConfigHistoryDto from(ConfigHistory history, boolean sensitive) {
        return new ConfigHistoryDto(
                history.getId(),
                history.getConfigKey(),
                maskIfPresent(history.getOldValue(), sensitive),
                maskIfPresent(history.getNewValue(), sensitive),
                history.getChangedBy(),
                history.getChangeReason(),
                history.getCreatedAt()
        );
    }

    private static String maskIfPresent(String value, boolean sensitive) {
        if (!sensitive || value == null || value.isEmpty()) {
            return value;
        }
        return MASK;
    }
}
