package com.omninest.modules.notification.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.omninest.common.messaging.QueueNames;
import com.omninest.common.preferences.UserPreferenceQuery;
import com.omninest.common.user.UserAccountQuery;
import com.omninest.modules.notification.config.NotificationEmailRuntimeConfig;
import com.omninest.modules.notification.domain.NotificationMessage;
import com.omninest.modules.notification.event.NotificationEmailRequestedEvent;
import com.omninest.modules.notification.repository.NotificationRepository;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import java.time.Instant;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

/**
 * 通知邮件通道的准入判定、任务登记与投递行为。
 *
 * @author OmniNest
 */
class NotificationEmailServiceTest {

    private static final UUID TASK_ID = UUID.fromString("60000000-0000-0000-0000-000000000001");
    private static final UUID USER_ID = UUID.fromString("60000000-0000-0000-0000-000000000002");
    private static final UUID NOTIFICATION_ID = UUID.fromString("60000000-0000-0000-0000-000000000003");

    private final NotificationRepository notificationRepository = mock(NotificationRepository.class);
    private final NotificationEmailRuntimeConfig runtimeConfig = mock(NotificationEmailRuntimeConfig.class);
    private final NotificationEmailSender emailSender = mock(NotificationEmailSender.class);
    private final UserPreferenceQuery userPreferenceQuery = mock(UserPreferenceQuery.class);
    private final UserAccountQuery userAccountQuery = mock(UserAccountQuery.class);
    private final TaskRecordService taskRecordService = mock(TaskRecordService.class);
    private final TaskDispatchService taskDispatchService = mock(TaskDispatchService.class);

    private final NotificationEmailService service = new NotificationEmailService(
            notificationRepository,
            runtimeConfig,
            emailSender,
            userPreferenceQuery,
            userAccountQuery,
            taskRecordService,
            taskDispatchService
    );

    @Test
    void shouldDeliverRequiresConfiguredChannelAndExplicitPreference() {
        when(runtimeConfig.configured()).thenReturn(false);
        assertThat(service.shouldDeliver(USER_ID)).isFalse();
        verifyNoInteractions(userPreferenceQuery);

        when(runtimeConfig.configured()).thenReturn(true);
        when(userPreferenceQuery.findValues(USER_ID, "notification")).thenReturn(Map.of());
        assertThat(service.shouldDeliver(USER_ID)).isFalse();

        when(userPreferenceQuery.findValues(USER_ID, "notification"))
                .thenReturn(Map.of("emailNotification", Boolean.TRUE));
        assertThat(service.shouldDeliver(USER_ID)).isTrue();
    }

    @Test
    void enqueueDeliveryWritesTaskRowAndOutboxInOneShot() {
        when(runtimeConfig.configured()).thenReturn(true);
        when(userPreferenceQuery.findValues(USER_ID, "notification"))
                .thenReturn(Map.of("emailNotification", Boolean.TRUE));

        var taskId = service.enqueueDelivery(USER_ID, NOTIFICATION_ID);

        assertThat(taskId).isPresent();
        ArgumentCaptor<Map<String, Object>> payload = ArgumentCaptor.forClass(Map.class);
        verify(taskRecordService).createQueuedTask(
                eq(taskId.get()),
                eq(USER_ID),
                eq(NotificationEmailService.TASK_TYPE),
                eq(QueueNames.NOTIFICATION_EMAIL_ROUTING_KEY),
                anyString(),
                eq("NOTIFICATION"),
                eq(NOTIFICATION_ID),
                payload.capture()
        );
        assertThat(payload.getValue())
                .containsOnlyKeys("taskId", "ownerUserId", "notificationId")
                .containsEntry("notificationId", NOTIFICATION_ID.toString());
        verify(taskDispatchService).enqueue(
                eq(taskId.get()),
                eq(QueueNames.TASK_EXCHANGE),
                eq(QueueNames.NOTIFICATION_EMAIL_ROUTING_KEY),
                any(NotificationEmailRequestedEvent.class)
        );
    }

    @Test
    void enqueueDeliveryStaysSilentWhenChannelIsOff() {
        when(runtimeConfig.configured()).thenReturn(false);

        assertThat(service.enqueueDelivery(USER_ID, NOTIFICATION_ID)).isEmpty();

        verifyNoInteractions(taskRecordService, taskDispatchService);
    }

    @Test
    void deliverSendsRenderedMessageAndCompletesTask() {
        givenClaimed();
        when(notificationRepository.findByIdAndRecipientUserId(NOTIFICATION_ID, USER_ID))
                .thenReturn(Optional.of(notification("任务已完成", "备份任务在 3 秒内完成")));
        when(userAccountQuery.findDeliverableEmail(USER_ID)).thenReturn(Optional.of("alex@omninest.local"));

        service.deliver(event());

        ArgumentCaptor<String> body = ArgumentCaptor.forClass(String.class);
        verify(emailSender).send(eq("alex@omninest.local"), eq("任务已完成"), body.capture());
        assertThat(body.getValue())
                .contains("备份任务在 3 秒内完成")
                .contains("通知类型：TASK_COMPLETED");
        verify(taskRecordService).markCompleted(eq(TASK_ID), any(Map.class));
    }

    @Test
    void deliverSkipsWhenAnotherConsumerAlreadyClaimed() {
        when(taskRecordService.claimForExecution(eq(TASK_ID), anyString())).thenReturn(false);

        service.deliver(event());

        verifyNoInteractions(notificationRepository, emailSender);
        verify(taskRecordService, never()).markCompleted(any(), any());
    }

    @Test
    void deliverCancelsWhenNotificationRowIsGone() {
        givenClaimed();
        when(notificationRepository.findByIdAndRecipientUserId(NOTIFICATION_ID, USER_ID))
                .thenReturn(Optional.empty());

        service.deliver(event());

        verify(taskRecordService).markCancelled(TASK_ID);
        verifyNoInteractions(emailSender);
    }

    @Test
    void deliverCancelsForAccountWithoutUsableEmail() {
        givenClaimed();
        when(notificationRepository.findByIdAndRecipientUserId(NOTIFICATION_ID, USER_ID))
                .thenReturn(Optional.of(notification("标题", "正文")));
        when(userAccountQuery.findDeliverableEmail(USER_ID)).thenReturn(Optional.empty());

        service.deliver(event());

        verify(taskRecordService).markCancelled(TASK_ID);
        verifyNoInteractions(emailSender);
    }

    @Test
    void sendTestMailUsesSenderDirectly() {
        service.sendTestMail("ops@omninest.local");

        verify(emailSender).send(eq("ops@omninest.local"), anyString(), anyString());
    }

    private void givenClaimed() {
        when(taskRecordService.claimForExecution(eq(TASK_ID), anyString())).thenReturn(true);
    }

    private NotificationEmailRequestedEvent event() {
        return new NotificationEmailRequestedEvent(TASK_ID, USER_ID, NOTIFICATION_ID);
    }

    private NotificationMessage notification(String title, String message) {
        return new NotificationMessage(
                NOTIFICATION_ID,
                USER_ID,
                "TASK_COMPLETED",
                title,
                message,
                Map.of(),
                null,
                Instant.parse("2026-10-20T02:00:00Z")
        );
    }
}
