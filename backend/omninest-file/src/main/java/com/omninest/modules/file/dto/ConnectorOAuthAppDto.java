package com.omninest.modules.file.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import java.time.Instant;

/**
 * OAuth 应用安全展示信息。
 *
 * @author OmniNest
 */
@Schema(description = "OAuth 应用配置")
public record ConnectorOAuthAppDto(
        @Schema(description = "ID") java.util.UUID id,
        @Schema(description = "连接器编码") String connectorCode,
        @Schema(description = "Client ID") String clientId,
        @Schema(description = "回调地址") String redirectUri,
        @Schema(description = "是否启用") boolean enabled,
        @Schema(description = "更新时间") Instant updatedAt
) {
}
