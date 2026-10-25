package com.omninest.modules.file.controller;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.ratelimit.RateLimitService;
import com.omninest.common.security.BrowserSecurityPolicy;
import com.omninest.common.security.ClientIpResolver;
import com.omninest.common.security.CurrentUserContext;
import com.omninest.modules.file.service.ExternalStorageOAuthService;
import com.omninest.modules.file.service.ExternalStorageService;
import com.omninest.modules.user.config.InitialSetupProperties;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.time.Duration;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;

/**
 * 外部存储控制器测试：OAuth 回调的结果页/回跳与匿名端点限流。
 *
 * @author OmniNest
 */
class ExternalStorageControllerTest {

    private static final String CALLBACK_PROVIDER = "ONEDRIVE";
    private static final String BINDING_NONCE = "binding-nonce";

    private final ExternalStorageService externalStorageService =
            mock(ExternalStorageService.class);
    private final CurrentUserContext currentUserContext = mock(CurrentUserContext.class);
    private final ExternalStorageOAuthService oauthService = mock(ExternalStorageOAuthService.class);
    private final RateLimitService rateLimitService = mock(RateLimitService.class);
    private final ClientIpResolver clientIpResolver = mock(ClientIpResolver.class);
    private final InitialSetupProperties setupProperties = new InitialSetupProperties();
    private final BrowserSecurityPolicy browserSecurityPolicy = mock(BrowserSecurityPolicy.class);
    private final HttpServletRequest request = mock(HttpServletRequest.class);
    private final HttpServletResponse servletResponse = mock(HttpServletResponse.class);

    private final ExternalStorageController controller = new ExternalStorageController(
            externalStorageService,
            currentUserContext,
            oauthService,
            rateLimitService,
            clientIpResolver,
            setupProperties,
            browserSecurityPolicy
    );

    @BeforeEach
    void stubRateLimit() {
        when(request.getRemoteAddr()).thenReturn("203.0.113.7");
        when(clientIpResolver.resolve(eq("203.0.113.7"), any(), any())).thenReturn("203.0.113.7");
        when(rateLimitService.tryAcquire(anyString(), eq(20), any(Duration.class))).thenReturn(true);
    }

    @Test
    @DisplayName("发起授权时向当前浏览器下发与 state 绑定的 HttpOnly Cookie")
    void oauthStartWritesBindingCookie() {
        UUID accountId = UUID.randomUUID();
        when(currentUserContext.requireCurrentUserId()).thenReturn(UUID.randomUUID());
        when(oauthService.start(any(), eq(CALLBACK_PROVIDER), eq(accountId)))
                .thenReturn(new ExternalStorageOAuthService.StartedAuthorization(
                        "https://provider.example/authorize?state=issued", "issued", "binding-nonce"));

        controller.oauthStart(CALLBACK_PROVIDER, accountId, servletResponse);

        ArgumentCaptor<String> cookie = ArgumentCaptor.forClass(String.class);
        verify(servletResponse).addHeader(eq(HttpHeaders.SET_COOKIE), cookie.capture());
        assertThat(cookie.getValue())
                .contains("omninest_oauth_binding=binding-nonce")
                .contains("HttpOnly")
                .contains("SameSite=Lax")
                .contains("Path=/api/v1/external-connectors");
    }

    @Test
    @DisplayName("已配置前端地址时回调 302 回 /files 并带上结果标记")
    void callbackRedirectsToConfiguredWebOrigin() {
        setupProperties.setWebBaseUrl("https://nest.example.com/");

        ResponseEntity<String> response = controller.oauthCallback(
                CALLBACK_PROVIDER, "state-value", "authorization-code", null,
                BINDING_NONCE, request, servletResponse);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.FOUND);
        assertThat(response.getHeaders().getLocation()).hasToString("https://nest.example.com/#/files?oauth=success");
        verify(oauthService).handleCallback(
                CALLBACK_PROVIDER, "state-value", "authorization-code", BINDING_NONCE);
    }

    @Test
    @DisplayName("三方报错分支只回跳 error，不触碰 token 交换")
    void callbackErrorBranchSkipsTokenExchange() {
        setupProperties.setWebBaseUrl("https://nest.example.com");

        ResponseEntity<String> response = controller.oauthCallback(
                CALLBACK_PROVIDER, "state-value", "authorization-code", "access_denied",
                BINDING_NONCE, request, servletResponse);

        assertThat(response.getHeaders().getLocation()).hasToString("https://nest.example.com/#/files?oauth=error");
        verify(oauthService, never()).handleCallback(
                anyString(), anyString(), anyString(), anyString());
    }

    @Test
    @DisplayName("未配置前端地址时返回无脚本结果页，不把用户留在裸 JSON")
    void callbackFallsBackToSelfContainedPage() {
        setupProperties.setWebBaseUrl(null);

        ResponseEntity<String> response = controller.oauthCallback(
                CALLBACK_PROVIDER, "state-value", "authorization-code", null,
                BINDING_NONCE, request, servletResponse);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getHeaders().getContentType()).isEqualTo(MediaType.TEXT_HTML);
        assertThat(response.getBody()).contains("授权成功");
    }

    @Test
    @DisplayName("前端地址不是 http/https 时不重定向，避免配置变成开放重定向")
    void callbackRejectsNonHttpRedirectTarget() {
        setupProperties.setWebBaseUrl("javascript:alert(1)");

        ResponseEntity<String> response = controller.oauthCallback(
                CALLBACK_PROVIDER, "state-value", "authorization-code", null,
                BINDING_NONCE, request, servletResponse);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getHeaders().getLocation()).isNull();
        assertThat(response.getBody()).contains("授权成功");
    }

    @Test
    @DisplayName("匿名回调端点按客户端地址限流，并返回结果页而不是裸 JSON")
    void callbackIsRateLimitedByClientIp() {
        when(rateLimitService.tryAcquire(
                "ip:203.0.113.7:external-oauth-callback", 20, Duration.ofMinutes(1)))
                .thenReturn(false);

        ResponseEntity<String> response = controller.oauthCallback(
                CALLBACK_PROVIDER, "state-value", "authorization-code", null,
                BINDING_NONCE, request, servletResponse);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getHeaders().getContentType()).isEqualTo(MediaType.TEXT_HTML);
        assertThat(response.getBody()).contains("授权已取消或失败");
        verify(oauthService, never()).handleCallback(
                anyString(), anyString(), anyString(), anyString());
    }

    @Test
    @DisplayName("state 过期等业务异常回跳前端结果页，不渲染裸 JSON")
    void callbackBusinessFailureRedirectsToErrorResult() {
        setupProperties.setWebBaseUrl("https://nest.example.com");
        doThrow(new BusinessException(ErrorCode.VALIDATION_FAILED, "state 已过期"))
                .when(oauthService).handleCallback(
                        CALLBACK_PROVIDER, "expired-state", "authorization-code", BINDING_NONCE);

        ResponseEntity<String> response = controller.oauthCallback(
                CALLBACK_PROVIDER, "expired-state", "authorization-code", null,
                BINDING_NONCE, request, servletResponse);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.FOUND);
        assertThat(response.getHeaders().getLocation()).hasToString("https://nest.example.com/#/files?oauth=error");
    }

    @Test
    @DisplayName("回调不要求 Bearer 令牌")
    void callbackDoesNotRequireCurrentUser() {
        setupProperties.setWebBaseUrl("https://nest.example.com");

        ResponseEntity<String> response = controller.oauthCallback(
                CALLBACK_PROVIDER, "state-value", "authorization-code", null,
                BINDING_NONCE, request, servletResponse);

        assertThat(response.getHeaders().getLocation()).isNotNull();
        verify(currentUserContext, never()).requireCurrentUserId();
    }
}
