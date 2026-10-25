package com.omninest.modules.user.controller;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verifyNoInteractions;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.ratelimit.RateLimitService;
import com.omninest.common.security.BrowserSecurityPolicy;
import com.omninest.common.security.ClientIpResolver;
import com.omninest.common.security.CurrentUserContext;
import com.omninest.common.security.RegistrationPolicy;
import com.omninest.modules.user.dto.RegisterRequest;
import com.omninest.modules.user.service.AuthService;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

class AuthControllerRegistrationTest {

    @Test
    void rejectsDisabledRegistrationBeforeRateLimitingOrUserCreation() {
        AuthService authService = mock(AuthService.class);
        BrowserSecurityPolicy browserSecurityPolicy = mock(BrowserSecurityPolicy.class);
        RateLimitService rateLimitService = mock(RateLimitService.class);
        RegistrationPolicy registrationPolicy = mock(RegistrationPolicy.class);
        ClientIpResolver clientIpResolver = mock(ClientIpResolver.class);
        AuthController controller = new AuthController(
                authService,
                browserSecurityPolicy,
                rateLimitService,
                registrationPolicy,
                clientIpResolver,
                mock(CurrentUserContext.class)
        );
        doThrow(new BusinessException(ErrorCode.REGISTRATION_DISABLED, "当前实例未开放用户注册"))
                .when(registrationPolicy)
                .requireRegistrationEnabled();

        assertThatThrownBy(() -> controller.register(
                new RegisterRequest("member", "Member", "member@example.com", "secret123"),
                "native",
                null,
                null,
                new MockHttpServletRequest(),
                new MockHttpServletResponse()
        )).isInstanceOfSatisfying(BusinessException.class, exception ->
                assertThat(exception.errorCode()).isEqualTo(ErrorCode.REGISTRATION_DISABLED));

        verifyNoInteractions(rateLimitService, authService, clientIpResolver);
    }
}
