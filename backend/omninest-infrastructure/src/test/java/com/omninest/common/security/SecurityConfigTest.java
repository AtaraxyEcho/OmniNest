package com.omninest.common.security;

import static org.assertj.core.api.Assertions.assertThat;

import com.omninest.common.config.SecurityProperties;
import java.time.Instant;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;
import org.springframework.mock.web.MockFilterChain;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.JwtClaimsSet;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.JwtEncoder;
import org.springframework.security.oauth2.jwt.JwtEncoderParameters;
import org.springframework.security.oauth2.jose.jws.MacAlgorithm;
import org.springframework.security.oauth2.jwt.JwsHeader;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;

/**
 * JWT 编解码配置回环测试。
 *
 * @author OmniNest
 */
class SecurityConfigTest {

    @AfterEach
    void clearSecurityContext() {
        SecurityContextHolder.clearContext();
    }

    @Test
    void hs256EncoderAndDecoderRoundTrip() {
        SecurityProperties properties = new SecurityProperties();
        properties.setJwtSecret("test-secret-for-hs256-round-trip-at-least-32-bytes");
        SecurityConfig config = new SecurityConfig();
        JwtEncoder encoder = config.jwtEncoder(properties);
        JwtDecoder decoder = config.jwtDecoder(properties);
        Instant issuedAt = Instant.now().minusSeconds(1);
        JwtClaimsSet claims = JwtClaimsSet.builder()
                .subject("10000000-0000-0000-0000-000000000001")
                .issuedAt(issuedAt)
                .expiresAt(issuedAt.plusSeconds(300))
                .claim("token_type", "access")
                .build();

        JwsHeader header = JwsHeader.with(MacAlgorithm.HS256).build();
        String token = encoder.encode(JwtEncoderParameters.from(header, claims)).getTokenValue();
        var decoded = decoder.decode(token);

        assertThat(decoded.getSubject()).isEqualTo(claims.getSubject());
        assertThat(decoded.getClaimAsString("token_type")).isEqualTo("access");
        assertThat(decoded.getHeaders().get("alg")).isEqualTo("HS256");
    }

    @Test
    void logoutFilterAuthenticatesValidTokenAndIgnoresExpiredToken() throws Exception {
        SecurityProperties properties = properties();
        SecurityConfig config = new SecurityConfig();
        LogoutBearerTokenFilter filter = config.logoutBearerTokenFilter(config.jwtDecoder(properties));

        String validToken = accessToken(config, properties, Instant.now().plusSeconds(300));
        filter.doFilter(
                logoutRequest(validToken),
                new MockHttpServletResponse(),
                new MockFilterChain()
        );
        assertThat(SecurityContextHolder.getContext().getAuthentication())
                .isInstanceOf(JwtAuthenticationToken.class);

        SecurityContextHolder.clearContext();
        String expiredToken = accessToken(config, properties, Instant.now().minusSeconds(60));
        filter.doFilter(
                logoutRequest(expiredToken),
                new MockHttpServletResponse(),
                new MockFilterChain()
        );
        assertThat(SecurityContextHolder.getContext().getAuthentication()).isNull();
    }

    @Test
    void bearerTokenResolverSkipsOnlyLogoutEndpoint() {
        SecurityConfig config = new SecurityConfig();
        var resolver = config.bearerTokenResolver();

        MockHttpServletRequest logout = new MockHttpServletRequest("POST", "/api/v1/auth/logout");
        logout.setServletPath("/api/v1/auth/logout");
        logout.addHeader(HttpHeaders.AUTHORIZATION, "Bearer token");
        assertThat(resolver.resolve(logout)).isNull();

        MockHttpServletRequest files = new MockHttpServletRequest("GET", "/api/v1/files");
        files.setServletPath("/api/v1/files");
        files.addHeader(HttpHeaders.AUTHORIZATION, "Bearer token");
        assertThat(resolver.resolve(files)).isEqualTo("token");
    }

    private SecurityProperties properties() {
        SecurityProperties properties = new SecurityProperties();
        properties.setJwtSecret("test-secret-for-hs256-round-trip-at-least-32-bytes");
        return properties;
    }

    private String accessToken(
            SecurityConfig config,
            SecurityProperties properties,
            Instant expiresAt
    ) {
        JwtClaimsSet claims = JwtClaimsSet.builder()
                .subject("10000000-0000-0000-0000-000000000001")
                .issuedAt(Instant.now().minusSeconds(120))
                .expiresAt(expiresAt)
                .claim("sid", "20000000-0000-0000-0000-000000000001")
                .claim("token_type", "access")
                .claim("token_use", "access")
                .build();
        return config.jwtEncoder(properties)
                .encode(JwtEncoderParameters.from(JwsHeader.with(MacAlgorithm.HS256).build(), claims))
                .getTokenValue();
    }

    private MockHttpServletRequest logoutRequest(String token) {
        MockHttpServletRequest request = new MockHttpServletRequest("POST", "/api/v1/auth/logout");
        request.setServletPath("/api/v1/auth/logout");
        request.addHeader(HttpHeaders.AUTHORIZATION, "Bearer " + token);
        return request;
    }
}
