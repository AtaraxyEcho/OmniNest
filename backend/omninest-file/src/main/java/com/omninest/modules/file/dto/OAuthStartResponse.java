package com.omninest.modules.file.dto;

import io.swagger.v3.oas.annotations.media.Schema;

/**
 * OAuth 授权开始结果。
 *
 * @author OmniNest
 */
@Schema(description = "OAuth 授权开始结果")
public record OAuthStartResponse(
        @Schema(description = "授权 URL") String authorizationUrl,
        @Schema(description = "state") String state
) {
}
