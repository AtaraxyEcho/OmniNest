package com.omninest.modules.file.dto;

import io.swagger.v3.oas.annotations.media.Schema;

/**
 * 保存 OAuth 应用请求。
 *
 * @author OmniNest
 */
@Schema(description = "保存 OAuth 应用请求")
public record SaveConnectorOAuthAppRequest(
        @Schema(description = "连接器编码", example = "ONEDRIVE") String connectorCode,
        @Schema(description = "Client ID") String clientId,
        @Schema(description = "Client Secret") String clientSecret,
        @Schema(description = "回调地址") String redirectUri,
        @Schema(description = "是否启用") boolean enabled
) {
}
