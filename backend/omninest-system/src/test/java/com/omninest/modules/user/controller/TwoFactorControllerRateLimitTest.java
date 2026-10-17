package com.omninest.modules.user.controller;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.ratelimit.RateLimitService;
import com.omninest.common.security.CurrentUserContext;
import com.omninest.modules.user.dto.TwoFactorDtos.TwoFactorDisableRequest;
import com.omninest.modules.user.dto.TwoFactorDtos.TwoFactorEnableRequest;
import com.omninest.modules.user.dto.TwoFactorDtos.TwoFactorSetupRequest;
import com.omninest.modules.user.service.TwoFactorPolicyService;
import com.omninest.modules.user.service.TwoFactorService;
import com.omninest.modules.user.service.UserSessionRevocationService;
import java.time.Duration;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * 自助两步验证接口的频率闸门测试：闸门必须在触碰凭据服务之前生效。
 *
 * @author OmniNest
 */
class TwoFactorControllerRateLimitTest {

    private final TwoFactorService twoFactorService = mock(TwoFactorService.class);
    private final TwoFactorPolicyService twoFactorPolicyService = mock(TwoFactorPolicyService.class);
    private final CurrentUserContext currentUserContext = mock(CurrentUserContext.class);
    private final RateLimitService rateLimitService = mock(RateLimitService.class);
    private final UserSessionRevocationService userSessionRevocationService =
            mock(UserSessionRevocationService.class);

    private TwoFactorController controller;
    private UUID userId;

    @BeforeEach
    void setUp() {
        controller = new TwoFactorController(
                twoFactorService,
                twoFactorPolicyService,
                currentUserContext,
                rateLimitService,
                userSessionRevocationService
        );
        userId = UUID.randomUUID();
        when(currentUserContext.requireCurrentUserId()).thenReturn(userId);
        when(rateLimitService.tryAcquire(anyString(), anyInt(), any(Duration.class))).thenReturn(true);
    }

    @Test
    @DisplayName("生成秘钥：按用户每小时 3 次计费")
    void setupChargesPerUserHourlyBudget() {
        controller.setup(new TwoFactorSetupRequest("secret123"));

        verify(rateLimitService).tryAcquire("user:" + userId + ":2fa-setup", 3, Duration.ofHours(1));
        verify(twoFactorService).startSetup(userId, "secret123");
    }

    @Test
    @DisplayName("生成秘钥：预算耗尽时不触碰凭据服务")
    void setupRejectsWhenBudgetExhausted() {
        when(rateLimitService.tryAcquire(eq("user:" + userId + ":2fa-setup"), anyInt(), any(Duration.class)))
                .thenReturn(false);

        assertThatThrownBy(() -> controller.setup(new TwoFactorSetupRequest("secret123")))
                .isInstanceOfSatisfying(BusinessException.class, exception ->
                        assertThat(exception.errorCode()).isEqualTo(ErrorCode.RATE_LIMITED));
        verifyNoInteractions(twoFactorService);
    }

    @Test
    @DisplayName("确认启用：按用户每分钟 5 次计费，覆盖验证码在线爆破")
    void enableChargesPerUserMinuteBudget() {
        controller.enable(new TwoFactorEnableRequest("123456"));

        verify(rateLimitService).tryAcquire("user:" + userId + ":2fa-enable", 5, Duration.ofMinutes(1));
        verify(twoFactorService).enable(userId, "123456");
    }

    @Test
    @DisplayName("确认启用：预算耗尽时不消费验证码")
    void enableRejectsWhenBudgetExhausted() {
        when(rateLimitService.tryAcquire(eq("user:" + userId + ":2fa-enable"), anyInt(), any(Duration.class)))
                .thenReturn(false);

        assertThatThrownBy(() -> controller.enable(new TwoFactorEnableRequest("123456")))
                .isInstanceOfSatisfying(BusinessException.class, exception ->
                        assertThat(exception.errorCode()).isEqualTo(ErrorCode.RATE_LIMITED));
        verifyNoInteractions(twoFactorService);
    }

    @Test
    @DisplayName("关闭：按用户每小时 3 次计费，覆盖密码复核爆破，并吊销其他会话")
    void disableChargesPerUserHourlyBudget() {
        controller.disable(new TwoFactorDisableRequest("secret123", "123456"));

        verify(rateLimitService).tryAcquire("user:" + userId + ":2fa-disable", 3, Duration.ofHours(1));
        verify(twoFactorService).disable(userId, "secret123", "123456");
        verify(userSessionRevocationService).revokeAllExcept(userId, null, "TWO_FACTOR_DISABLED");
    }

    @Test
    @DisplayName("关闭：预算耗尽时不清除凭据")
    void disableRejectsWhenBudgetExhausted() {
        when(rateLimitService.tryAcquire(eq("user:" + userId + ":2fa-disable"), anyInt(), any(Duration.class)))
                .thenReturn(false);

        assertThatThrownBy(() -> controller.disable(new TwoFactorDisableRequest("secret123", "123456")))
                .isInstanceOfSatisfying(BusinessException.class, exception ->
                        assertThat(exception.errorCode()).isEqualTo(ErrorCode.RATE_LIMITED));
        verifyNoInteractions(twoFactorService);
    }

    @Test
    @DisplayName("关闭：角色被策略强制时直接拒绝，不计费也不触碰凭据服务")
    void disableRejectsForMandatoryRole() {
        when(twoFactorPolicyService.isRequired(userId)).thenReturn(true);

        assertThatThrownBy(() -> controller.disable(new TwoFactorDisableRequest("secret123", "123456")))
                .isInstanceOfSatisfying(BusinessException.class, exception ->
                        assertThat(exception.errorCode()).isEqualTo(ErrorCode.FORBIDDEN));
        verifyNoInteractions(twoFactorService, rateLimitService, userSessionRevocationService);
    }

    @Test
    @DisplayName("状态查询不计费：只读接口不消耗写操作预算")
    void statusDoesNotChargeBudget() {
        when(twoFactorService.isEnabled(userId)).thenReturn(true);
        when(twoFactorPolicyService.isRequired(userId)).thenReturn(false);

        var response = controller.status();

        assertThat(response.getData().enabled()).isTrue();
        verifyNoInteractions(rateLimitService);
    }
}
