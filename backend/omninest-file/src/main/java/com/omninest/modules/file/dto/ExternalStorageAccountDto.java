package com.omninest.modules.file.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import java.time.Instant;
import java.util.Map;
import java.util.UUID;

/**
 * 外部存储账户的安全展示信息。
 *
 * @author OmniNest
 */
@Schema(description = "外部存储账户信息")
public record ExternalStorageAccountDto(
        @Schema(description = "账户 ID") UUID id,
        @Schema(description = "存储提供者", example = "S3") String provider,
        @Schema(description = "显示名称", example = "我的网盘") String displayName,
        @Schema(description = "不包含密钥、密码和令牌的可编辑连接元数据") Map<String, String> connectionMetadata,
        @Schema(description = "是否已经保存连接凭据") boolean credentialsConfigured,
        @Schema(description = "状态", example = "ACTIVE") String status,
        @Schema(description = "最近错误码") String lastErrorCode,
        @Schema(description = "最近检查时间") Instant lastCheckedAt,
        @Schema(description = "创建时间") Instant createdAt,
        @Schema(description = "更新时间") Instant updatedAt
) {
}
