package com.omninest.modules.user.controller;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.ratelimit.RateLimitService;
import com.omninest.common.security.BrowserSecurityPolicy;
import com.omninest.common.security.ClientIpResolver;
import com.omninest.common.security.RegistrationPolicy;
import com.omninest.modules.user.dto.AuthTokenResponse;
import com.omninest.modules.user.dto.AuthUserDto;
import com.omninest.modules.user.dto.LoginRequest;
import com.omninest.modules.user.dto.RefreshRequest;
import com.omninest.modules.user.service.AuthService;
import jakarta.servlet.http.Cookie;
import java.time.Duration;
import java.util.Set;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import tools.jackson.databind.ObjectMapper;

class AuthControllerCookieTest {
    private final AuthService authService = mock(AuthService.class);
    private final BrowserSecurityPolicy browserSecurityPolicy = mock(BrowserSecurityPolicy.class);
    private final RateLimitService rateLimitService = mock(RateLimitService.class);
    private final RegistrationPolicy registrationPolicy = mock(RegistrationPolicy.class);
    private final ClientIpResolver clientIpResolver = mock(ClientIpResolver.class);
    private final ObjectMapper objectMapper = new ObjectMapper();

    private AuthController controller;
    private AuthTokenResponse token;

    @BeforeEach
    void setUp() {
        controller = new AuthController(
                authService,
                browserSecurityPolicy,
                rateLimitService,
                registrationPolicy,
                clientIpResolver
        );
        token = tokenResponse();
        when(rateLimitService.tryAcquire(anyString(), anyInt(), any(Duration.class))).thenReturn(true);
        when(clientIpResolver.resolve(anyString(), any(), any())).thenReturn("203.0.113.8");
        when(authService.login(any(LoginRequest.class), anyString(), anyString(), anyString(), anyString(), anyString()))
                .thenReturn(token);
    }

    @Test
    void webLoginWritesHttpOnlyCookieAndOmitsRefreshTokenFromBody() throws Exception {
        MockHttpServletResponse servletResponse = new MockHttpServletResponse();

        var response = controller.login(
                new LoginRequest("root", "secret"),
                "web",
                "browser-1",
                "Chrome",
                request(),
                servletResponse
        );

        assertThat(response.getData().refreshToken()).isNull();
        assertThat(objectMapper.writeValueAsString(response)).doesNotContain("refreshToken");
        assertThat(servletResponse.getHeader(HttpHeaders.SET_COOKIE))
                .contains("omninest_refresh_token=refresh-token")
                .contains("HttpOnly")
                .contains("SameSite=Strict");
    }

    @Test
    void nativeLoginKeepsRefreshTokenInBodyAndDoesNotWriteCookie() {
        MockHttpServletResponse servletResponse = new MockHttpServletResponse();

        var response = controller.login(
                new LoginRequest("root", "secret"),
                "android",
                "phone-1",
                "Pixel",
                request(),
                servletResponse
        );

        assertThat(response.getData().refreshToken()).isEqualTo("refresh-token");
        assertThat(servletResponse.getHeader(HttpHeaders.SET_COOKIE)).isNull();
    }

    @Test
    void webLogoutRevokesSessionFromCookieAndClearsCookie() {
        MockHttpServletResponse servletResponse = new MockHttpServletResponse();
        MockHttpServletRequest servletRequest = request();
        servletRequest.setCookies(new Cookie("omninest_refresh_token", "refresh-token"));

        controller.logout(new RefreshRequest(null), "web", servletRequest, servletResponse);

        verify(authService).logout("refresh-token");
        assertThat(servletResponse.getHeader(HttpHeaders.SET_COOKIE))
                .contains("omninest_refresh_token=")
                .contains("Max-Age=0")
                .contains("HttpOnly")
                .contains("SameSite=Strict");
    }

    @Test
    void sameSiteNoneForcesSecureCookie() throws Exception {
        when(browserSecurityPolicy.refreshCookieSameSite()).thenReturn("None");
        MockHttpServletResponse servletResponse = new MockHttpServletResponse();

        controller.login(
                new LoginRequest("root", "secret"),
                "web",
                "browser-1",
                "Chrome",
                request(),
                servletResponse
        );

        // SameSite=None 不带 Secure 会被浏览器整体拒绝，必须强制安全传输。
        assertThat(servletResponse.getHeader(HttpHeaders.SET_COOKIE))
                .contains("SameSite=None")
                .contains("Secure");
    }

    @Test
    void sameSiteLaxPassesThroughWithoutForcingSecure() throws Exception {
        when(browserSecurityPolicy.refreshCookieSameSite()).thenReturn("LAX");
        MockHttpServletResponse servletResponse = new MockHttpServletResponse();

        controller.login(
                new LoginRequest("root", "secret"),
                "web",
                "browser-1",
                "Chrome",
                request(),
                servletResponse
        );

        assertThat(servletResponse.getHeader(HttpHeaders.SET_COOKIE))
                .contains("SameSite=Lax")
                .doesNotContain("Secure");
    }

    @Test
    void nullPolicySameSiteFallsBackToStrict() throws Exception {
        when(browserSecurityPolicy.refreshCookieSameSite()).thenReturn(null);
        MockHttpServletResponse servletResponse = new MockHttpServletResponse();

        controller.login(
                new LoginRequest("root", "secret"),
                "web",
                "browser-1",
                "Chrome",
                request(),
                servletResponse
        );

        assertThat(servletResponse.getHeader(HttpHeaders.SET_COOKIE))
                .contains("SameSite=Strict");
    }

    @Test
    void nativeLogoutRevokesSessionFromBodyToken() {
        MockHttpServletResponse servletResponse = new MockHttpServletResponse();

        controller.logout(
                new RefreshRequest("refresh-token"),
                "android",
                request(),
                servletResponse
        );

        verify(authService).logout("refresh-token");
    }

    private MockHttpServletRequest request() {
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setRemoteAddr("127.0.0.1");
        request.addHeader("User-Agent", "test-agent");
        return request;
    }

    private AuthTokenResponse tokenResponse() {
        AuthUserDto user = new AuthUserDto(
                UUID.fromString("10000000-0000-0000-0000-000000000001"),
                "root",
                "Root",
                null,
                "root@example.com",
                "ACTIVE",
                "SUPER_ADMIN",
                Set.of("SUPER_ADMIN"),
                Set.of("system:config:manage"),
                1024,
                0
        );
        return new AuthTokenResponse(
                "Bearer",
                "access-token",
                "2026-08-24T12:30:00Z",
                "refresh-token",
                "2026-09-24T12:00:00Z",
                user
        );
    }
}
