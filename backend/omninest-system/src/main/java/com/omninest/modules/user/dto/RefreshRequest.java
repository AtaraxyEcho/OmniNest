package com.omninest.modules.user.dto;

import io.swagger.v3.oas.annotations.media.Schema;

@Schema(description = "刷新令牌请求")
public record RefreshRequest(
        @Schema(description = "刷新令牌", example = "eyJhbGciOiJIUzI1NiJ9...") String refreshToken
) {
}
