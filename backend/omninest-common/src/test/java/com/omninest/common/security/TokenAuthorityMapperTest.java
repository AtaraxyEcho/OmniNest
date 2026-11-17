package com.omninest.common.security;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;

/**
 * 验证令牌声明到系统权限编码的映射规则。
 *
 * @author OmniNest
 */
class TokenAuthorityMapperTest {

    @Test
    void mapsAccessTokenRolesAndPermissions() {
        Map<String, Object> claims = Map.of(
                "token_use", "access",
                "roles", List.of("ADMIN", "ROLE_USER"),
                "permissions", List.of(Permissions.SYSTEM_CONFIG_MANAGE)
        );

        assertThat(TokenAuthorityMapper.map(claims)).containsExactly(
                TokenAuthorityMapper.ACCESS_TOKEN_AUTHORITY,
                "ROLE_ADMIN",
                "ROLE_USER",
                Permissions.SYSTEM_CONFIG_MANAGE
        );
    }

    @Test
    void mapsFallbackRoleAndStringClaims() {
        Map<String, Object> claims = Map.of(
                "token_use", "access",
                "role", "USER",
                "permissions", Permissions.FILE_READ
        );

        assertThat(TokenAuthorityMapper.map(claims)).containsExactly(
                TokenAuthorityMapper.ACCESS_TOKEN_AUTHORITY,
                "ROLE_USER",
                Permissions.FILE_READ
        );
    }

    @Test
    void ignoresRefreshTokenAuthorities() {
        Map<String, Object> claims = Map.of(
                "token_use", "refresh",
                "roles", List.of("ADMIN")
        );

        assertThat(TokenAuthorityMapper.map(claims)).isEmpty();
    }
}
