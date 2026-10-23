package com.omninest.modules.user.controller;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.ratelimit.RateLimitService;
import com.omninest.common.security.ClientIpResolver;
import com.omninest.modules.user.dto.InitialSetupRequest;
import com.omninest.modules.user.service.InitialSetupService;
import jakarta.servlet.http.HttpServletRequest;
import org.junit.jupiter.api.Test;

/**
 * 首次安装入口限流顺序测试。
 *
 * @author OmniNest
 */
class InitialSetupControllerTest {

    @Test
    void invalidSetupTokenDoesNotConsumeGlobalBucket() {
        InitialSetupService initialSetupService = mock(InitialSetupService.class);
        RateLimitService rateLimitService = mock(RateLimitService.class);
        ClientIpResolver clientIpResolver = mock(ClientIpResolver.class);
        HttpServletRequest request = mock(HttpServletRequest.class);
        when(request.getRemoteAddr()).thenReturn("127.0.0.1");
        when(clientIpResolver.resolve("127.0.0.1", null, null)).thenReturn("203.0.113.10");
        when(rateLimitService.tryAcquire(eq("setup:ip:203.0.113.10"), eq(5), any()))
                .thenReturn(true);
        doThrow(new BusinessException(ErrorCode.FORBIDDEN, "安装凭据无效"))
                .when(initialSetupService).validateSetupToken("wrong-token");
        InitialSetupController controller =
                new InitialSetupController(initialSetupService, rateLimitService, clientIpResolver);

        assertThatThrownBy(() -> controller.createSuperAdmin(
                "wrong-token", requestBody(), request))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("安装凭据无效");

        verify(rateLimitService, never()).tryAcquire(eq("setup:global"), anyInt(), any());
        verify(initialSetupService, never()).createSuperAdmin(any(), any());
    }

    private InitialSetupRequest requestBody() {
        return new InitialSetupRequest(
                "root", null, null, "password-123", null, null, null, null, null);
    }
}
