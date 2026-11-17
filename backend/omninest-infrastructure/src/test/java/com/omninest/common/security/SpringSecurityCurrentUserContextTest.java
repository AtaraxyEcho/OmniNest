package com.omninest.common.security;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.omninest.common.error.BusinessException;
import java.time.Instant;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;

class SpringSecurityCurrentUserContextTest {
    private final CurrentUserContext currentUserContext = new SpringSecurityCurrentUserContext();

    @AfterEach
    void clearSecurityContext() {
        SecurityContextHolder.clearContext();
    }

    @Test
    void resolvesCurrentUserFromJwtAuthentication() {
        Jwt jwt = jwt(
                "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
                Map.of(
                        "username", "root",
                        "roles", List.of(Roles.ADMIN),
                        "permissions", List.of(Permissions.SYSTEM_CONFIG_MANAGE)
                )
        );
        SecurityContextHolder.getContext().setAuthentication(authenticatedToken(jwt));

        CurrentUser currentUser = currentUserContext.requireCurrentUser();

        assertThat(currentUser.userId()).hasToString("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
        assertThat(currentUser.username()).isEqualTo("root");
        assertThat(currentUser.roles()).containsExactly(Roles.ADMIN);
        assertThat(currentUser.permissions()).containsExactly(Permissions.SYSTEM_CONFIG_MANAGE);
    }

    @Test
    void rejectsMissingAuthentication() {
        assertThatThrownBy(currentUserContext::requireCurrentUser)
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("未认证");
    }

    @Test
    void rejectsInvalidJwtSubject() {
        SecurityContextHolder.getContext().setAuthentication(authenticatedToken(jwt("bad-subject", Map.of())));

        assertThatThrownBy(currentUserContext::requireCurrentUser)
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("登录凭证无效");
    }

    private Jwt jwt(String subject, Map<String, Object> extraClaims) {
        var claims = new HashMap<String, Object>(extraClaims);
        claims.put("sub", subject);
        return new Jwt(
                "token",
                Instant.parse("2026-05-20T00:00:00Z"),
                Instant.parse("2026-05-20T01:00:00Z"),
                Map.of("alg", "HS256"),
                claims
        );
    }

    private JwtAuthenticationToken authenticatedToken(Jwt jwt) {
        return new JwtAuthenticationToken(jwt, List.of(new SimpleGrantedAuthority("ROLE_USER")));
    }
}
