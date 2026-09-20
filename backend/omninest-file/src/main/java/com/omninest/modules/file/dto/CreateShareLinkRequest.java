package com.omninest.modules.file.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotNull;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;
import java.util.List;
import java.util.UUID;

@Schema(description = "创建分享链接请求")
public record CreateShareLinkRequest(
        @Schema(description = "资源 ID", example = "550e8400-e29b-41d4-a716-446655440000") @NotNull UUID resourceId,
        @Schema(description = "资源类型", example = "FILE", allowableValues = {"FILE", "FOLDER"}) String resourceType,
        @Schema(description = "自定义访问密码") String password,
        @Schema(description = "是否自动生成密码", example = "false") boolean generatePassword,
        @Schema(
                description = "过期时间；接受 ISO-8601 即时区标记或 yyyy-MM-dd HH:mm:ss（按 UTC），由 parsedExpiresAt() 统一转 Instant",
                example = "2026-09-26T00:00:00Z"
        ) String expiresAt,
        @Schema(description = "最大访问次数", example = "100") Integer maxAccessCount,
        @Schema(description = "指定接收用户 ID 列表") List<UUID> recipientUserIds
) {
    private static final DateTimeFormatter LEGACY_FORMATTER =
            DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    /**
     * 解析过期时间为 Instant。
     *
     * <p>项目 JSON 层（FastJson 全局）以 {@code yyyy-MM-dd HH:mm:ss} 为线格式，
     * 但客户端（如前端分享面板）与 Swagger 契约按 ISO-8601 即时区（Instant 的
     * 自然表达）发送；此前仅 FastJson 格式可解析，ISO-8601 抛 500（D-011）。
     * 现统一兼容双格式：含 'T'/'Z'/'+' 视为 ISO-8601 即时，否则按
     * {@code yyyy-MM-dd HH:mm:ss} 的 UTC；空串/空白返回 null。
     *
     * @throws DateTimeParseException 两种格式均不匹配时（全局异常处理器映射为参数错误）
     */
    public Instant parsedExpiresAt() {
        if (expiresAt == null || expiresAt.isBlank()) {
            return null;
        }
        String trimmed = expiresAt.trim();
        boolean isoLike = trimmed.indexOf('T') > 0 || trimmed.endsWith("Z") || trimmed.indexOf('+') > 0;
        if (isoLike) {
            return Instant.parse(trimmed);
        }
        return LocalDateTime.parse(trimmed, LEGACY_FORMATTER).toInstant(ZoneOffset.UTC);
    }
}
