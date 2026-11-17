package com.omninest.common.security;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.springframework.security.oauth2.jwt.Jwt;

/**
 * 验证通用权限编码到 Spring Security 权限对象的适配。
 *
 * @author OmniNest
 */
class JwtAuthorityConverterTest {

    private final JwtAuthorityConverter converter = new JwtAuthorityConverter();

    @Test
    void convertsRolesAndPermissionsToAuthorities() {
        Jwt jwt = new Jwt(
                "token",
                Instant.parse("2026-05-19T00:00:00Z"),
                Instant.parse("2026-05-19T01:00:00Z"),
                Map.of("alg", "HS256"),
                Map.of(
                        "sub", "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
                        "token_use", "access",
                        "roles", List.of("ADMIN"),
                        "permissions", List.of(Permissions.SYSTEM_CONFIG_MANAGE)
                )
        );

        var authorities = converter.convert(jwt);

        assertThat(authorities).extracting("authority")
                .containsExactlyInAnyOrder(
                        TokenAuthorityMapper.ACCESS_TOKEN_AUTHORITY,
                        "ROLE_ADMIN",
                        Permissions.SYSTEM_CONFIG_MANAGE
                );
    }

    @Test
    void ignoresRefreshTokenAuthorities() {
        Jwt jwt = new Jwt(
                "token",
                Instant.parse("2026-05-19T00:00:00Z"),
                Instant.parse("2026-05-19T01:00:00Z"),
                Map.of("alg", "HS256"),
                Map.of(
                        "sub", "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
                        "token_use", "refresh",
                        "roles", List.of("ADMIN"),
                        "permissions", List.of(Permissions.SYSTEM_CONFIG_MANAGE)
                )
        );

        var authorities = converter.convert(jwt);

        assertThat(authorities).isEmpty();
    }
}
