package com.omninest.modules.notification.controller;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.error.BusinessException;
import com.omninest.common.security.CurrentUserContext;
import com.omninest.common.user.UserAccountQuery;
import com.omninest.modules.notification.dto.EmailTestRequest;
import com.omninest.modules.notification.service.NotificationEmailService;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;

/**
 * 邮件通道测试接口的收件人解析。
 *
 * @author OmniNest
 */
class NotificationEmailAdminControllerTest {

    private static final UUID ADMIN_ID = UUID.fromString("b0000000-0000-0000-0000-000000000001");

    private final CurrentUserContext currentUserContext = mock(CurrentUserContext.class);
    private final UserAccountQuery userAccountQuery = mock(UserAccountQuery.class);
    private final NotificationEmailService emailService = mock(NotificationEmailService.class);
    private final NotificationEmailAdminController controller =
            new NotificationEmailAdminController(currentUserContext, userAccountQuery, emailService);

    @Test
    void usesRequestedRecipientAndTrimsSurroundingSpace() {
        var response = controller.emailTest(new EmailTestRequest("  ops@omninest.local  "));

        assertThat(response.getData()).isNull();
        verify(emailService).sendTestMail("ops@omninest.local");
    }

    @Test
    void fallsBackToTheCallerOwnMailbox() {
        when(currentUserContext.requireCurrentUserId()).thenReturn(ADMIN_ID);
        when(userAccountQuery.findDeliverableEmail(ADMIN_ID)).thenReturn(Optional.of("admin@omninest.local"));

        controller.emailTest(new EmailTestRequest(""));

        verify(emailService).sendTestMail("admin@omninest.local");
    }

    @Test
    void missingMailboxOnBothSidesFailsWithClearReason() {
        when(currentUserContext.requireCurrentUserId()).thenReturn(ADMIN_ID);
        when(userAccountQuery.findDeliverableEmail(ADMIN_ID)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> controller.emailTest(null))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("邮箱");

        verify(emailService, never()).sendTestMail(anyString());
    }
}
