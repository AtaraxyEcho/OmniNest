package com.omninest.modules.notification.controller;

import com.omninest.common.api.ApiResponse;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.security.CurrentUserContext;
import com.omninest.common.security.Permissions;
import com.omninest.common.user.UserAccountQuery;
import com.omninest.modules.notification.dto.EmailTestRequest;
import com.omninest.modules.notification.service.NotificationEmailService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
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

    @Operation(summary = "发送测试邮件", description = "按当前 SMTP 配置同步发送一封测试邮件；收件人留空时发给当前管理员")
    @PostMapping("/api/v1/admin/notifications/email-test")
    @PreAuthorize("hasAuthority('" + Permissions.SYSTEM_CONFIG_MANAGE + "')")
    ApiResponse<Void> emailTest(@RequestBody(required = false) EmailTestRequest request) {
        String recipient = request == null ? "" : request.to();
        if (recipient == null || recipient.isBlank()) {
            recipient = userAccountQuery
                    .findDeliverableEmail(currentUserContext.requireCurrentUserId())
                    .orElseThrow(() -> new BusinessException(ErrorCode.BAD_REQUEST, "当前账户没有可用于测试的邮箱"));
        }
        notificationEmailService.sendTestMail(recipient.trim());
        return ApiResponse.success(null);
    }
}
