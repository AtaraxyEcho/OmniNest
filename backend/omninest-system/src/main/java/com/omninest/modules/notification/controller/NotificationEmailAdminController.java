package com.omninest.modules.notification.controller;

import com.omninest.common.api.ApiResponse;
import com.omninest.common.audit.AdminAuditRecorder;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.ratelimit.RateLimitService;
import com.omninest.common.security.CurrentUserContext;
import com.omninest.common.security.FreshAdminActorVerifier;
import com.omninest.common.security.Permissions;
import com.omninest.common.user.UserAccountQuery;
import com.omninest.modules.notification.dto.EmailTestRequest;
import com.omninest.modules.notification.service.NotificationEmailService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import java.time.Duration;
import java.util.Map;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

/**
 * 通知邮件通道管理接口。
 *
 * <p>SMTP 参数本身在配置中心维护，这里只提供一个同步的连通性验证入口，
 * 让管理员改完配置立刻知道能不能发出去，而不是等下一条通知。</p>
 */
@RestController
@RequiredArgsConstructor
@Tag(name = "通知", description = "通知邮件通道管理")
public class NotificationEmailAdminController {

    private final CurrentUserContext currentUserContext;
    private final UserAccountQuery userAccountQuery;
    private final NotificationEmailService notificationEmailService;
    private final RateLimitService rateLimitService;
    private final FreshAdminActorVerifier adminActorGuard;
    private final AdminAuditRecorder adminAuditRecorder;

    @Operation(summary = "发送测试邮件", description = "按当前 SMTP 配置同步发送一封测试邮件；收件人留空时发给当前管理员")
    @PostMapping("/api/v1/admin/notifications/email-test")
    @PreAuthorize("hasAuthority('" + Permissions.SYSTEM_CONFIG_MANAGE + "')")
    ApiResponse<Void> emailTest(@Valid @RequestBody(required = false) EmailTestRequest request) {
        UUID actorUserId = currentUserContext.requireCurrentUserId();
        adminActorGuard.requireFreshAdminActor(actorUserId);
        if (!rateLimitService.tryAcquire(
                "admin:notification-email-test:" + actorUserId, 3, Duration.ofMinutes(1))) {
            throw new BusinessException(ErrorCode.RATE_LIMITED, "测试邮件发送过于频繁，请稍后再试");
        }
        String recipient = request == null ? "" : request.to();
        if (recipient == null || recipient.isBlank()) {
            recipient = userAccountQuery
                    .findDeliverableEmail(actorUserId)
                    .orElseThrow(() -> new BusinessException(ErrorCode.BAD_REQUEST, "当前账户没有可用于测试的邮箱"));
        }
        notificationEmailService.sendTestMail(recipient.trim());
        adminAuditRecorder.recordWithMetadata(
                actorUserId,
                "ADMIN_NOTIFICATION_EMAIL_TEST",
                "notification_email",
                null,
                Map.of("recipientDomain", emailDomain(recipient))
        );
        return ApiResponse.success(null);
    }

    /**
     * 审计只记录域名，避免把收件人完整邮箱写入管理端日志。
     */
    private String emailDomain(String recipient) {
        int at = recipient.lastIndexOf('@');
        return at < 0 || at == recipient.length() - 1 ? "" : recipient.substring(at + 1).trim();
    }
}
