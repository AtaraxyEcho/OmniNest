package com.omninest.modules.user.dto;

import com.fasterxml.jackson.annotation.JsonInclude;
import io.swagger.v3.oas.annotations.media.Schema;
import java.util.List;

@Schema(description = "认证令牌响应")
@JsonInclude(JsonInclude.Include.NON_NULL)
public record AuthTokenResponse(
        @Schema(description = "令牌类型", example = "Bearer") String tokenType,
        @Schema(description = "访问令牌", example = "eyJhbGciOiJIUzI1NiJ9...") String accessToken,
        @Schema(description = "访问令牌过期时间", example = "2026-06-07T12:00:00Z") String expiresAt,
        @Schema(description = "刷新令牌", example = "eyJhbGciOiJIUzI1NiJ9...") String refreshToken,
        @Schema(description = "刷新令牌过期时间", example = "2026-06-14T12:00:00Z") String refreshExpiresAt,
        @Schema(description = "当前用户信息") AuthUserDto user,
        @Schema(description = "是否需要两步验证；为 true 时不签发令牌") Boolean twoFactorRequired,
        @Schema(description = "两步验证挑战令牌（5 分钟有效）") String challengeToken,
        @Schema(description = "挑战类型：verify=已启用待验证，enroll=强制角色待注册") String challengeType,
        @Schema(description = "挑战令牌过期时间") String challengeExpiresAt,
        @Schema(description = "一次性备份码，仅注册引导启用成功时返回") List<String> backupCodes
) {
    /**
     * 普通令牌响应构造。
     *
     * @param tokenType 令牌类型
     * @param accessToken 访问令牌
     * @param expiresAt 访问令牌过期时间
     * @param refreshToken 刷新令牌
     * @param refreshExpiresAt 刷新令牌过期时间
     * @param user 当前用户
     */
    public AuthTokenResponse(
            String tokenType,
            String accessToken,
            String expiresAt,
            String refreshToken,
            String refreshExpiresAt,
            AuthUserDto user
    ) {
        this(tokenType, accessToken, expiresAt, refreshToken, refreshExpiresAt, user,
                null, null, null, null, null);
    }

    /**
     * 创建不包含刷新凭证的浏览器响应。
     *
     * @return 浏览器认证响应
     */
    public AuthTokenResponse withoutRefreshToken() {
        return new AuthTokenResponse(
                tokenType,
                accessToken,
                expiresAt,
                null,
                refreshExpiresAt,
                user,
                twoFactorRequired,
                challengeToken,
                challengeType,
                challengeExpiresAt,
                backupCodes
        );
    }
}
