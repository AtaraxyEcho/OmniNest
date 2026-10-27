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
import com.omninest.common.user.SystemInstanceInfo;
import com.omninest.common.user.UserAccountQuery;
import com.omninest.modules.notification.config.NotificationEmailRuntimeConfig;
import com.omninest.modules.notification.config.NotificationEmailRuntimeConfig.MessageFormat;
import com.omninest.modules.notification.domain.NotificationMessage;
import com.omninest.modules.notification.domain.NotificationType;
import com.omninest.modules.notification.event.NotificationEmailRequestedEvent;
import com.omninest.modules.notification.repository.NotificationRepository;
import com.omninest.modules.notification.repository.NotificationTypeRepository;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import java.time.Instant;
import java.time.ZoneId;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

/**
 * 通知邮件通道的准入判定、限速与投递行为。
 *
 * <p>渲染器用真实实现：正文的转义与降级同样是本通道要保证的行为，桩掉它就等于没测。</p>
 *
 * @author OmniNest
 */
class NotificationEmailServiceTest {

    private static final UUID TASK_ID = UUID.fromString("60000000-0000-0000-0000-000000000001");
    private static final UUID USER_ID = UUID.fromString("60000000-0000-0000-0000-000000000002");
    private static final UUID NOTIFICATION_ID = UUID.fromString("60000000-0000-0000-0000-000000000003");

    private final NotificationRepository notificationRepository = mock(NotificationRepository.class);
    private final NotificationTypeRepository notificationTypeRepository = mock(NotificationTypeRepository.class);
    private final NotificationEmailRuntimeConfig runtimeConfig = mock(NotificationEmailRuntimeConfig.class);
    private final NotificationEmailSender emailSender = mock(NotificationEmailSender.class);
    private final UserPreferenceQuery userPreferenceQuery = mock(UserPreferenceQuery.class);
    private final UserAccountQuery userAccountQuery = mock(UserAccountQuery.class);
    private final TaskRecordService taskRecordService = mock(TaskRecordService.class);
    private final TaskDispatchService taskDispatchService = mock(TaskDispatchService.class);
    private final com.omninest.common.user.SystemInstanceInfo systemInstanceInfo =
            mock(com.omninest.common.user.SystemInstanceInfo.class);

    /** 渲染器按真实实现装配，因此实例名/语言/时区必须给出确定值。 */
    private final SystemInstanceInfo instanceConfig = stubInstanceConfig();

    private final NotificationEmailService service = new NotificationEmailService(
            notificationRepository,
            notificationTypeRepository,
            runtimeConfig,
            emailSender,
            new NotificationEmailRenderer(instanceConfig),
            userPreferenceQuery,
            userAccountQuery,
            taskRecordService,
            taskDispatchService,
            systemInstanceInfo
    );

    {
        when(systemInstanceInfo.timeZone()).thenReturn(ZoneId.of("UTC"));
    }

    private static SystemInstanceInfo stubInstanceConfig() {
        SystemInstanceInfo config = mock(SystemInstanceInfo.class);
        when(config.instanceName()).thenReturn("OmniNest");
        when(config.defaultLocale()).thenReturn("zh-CN");
        when(config.timeZone()).thenReturn(ZoneId.of("UTC"));
        return config;
    }

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
    void shouldDeliverSkipsEmailInsideQuietHours() {
        when(runtimeConfig.configured()).thenReturn(true);
        when(systemInstanceInfo.timeZone()).thenReturn(ZoneId.of("UTC"));
        // UTC 当前时刻 + 2 小时作为窗口中点，保证跨零点与同日两种形态都命中。
        java.time.LocalTime now = java.time.LocalTime.now(ZoneId.of("UTC")).withSecond(0).withNano(0);
        java.time.format.DateTimeFormatter clock = java.time.format.DateTimeFormatter.ofPattern("HH:mm");
        String start = now.minusHours(1).format(clock);
        String end = now.plusHours(1).format(clock);
        when(userPreferenceQuery.findValues(USER_ID, "notification")).thenReturn(Map.of(
                "emailNotification", Boolean.TRUE,
                "quietHours", Map.of("enabled", Boolean.TRUE, "start", start, "end", end)
        ));

        assertThat(service.shouldDeliver(USER_ID)).isFalse();
    }

    @Test
    void shouldDeliverIgnoresInvalidQuietHoursWindow() {
        when(runtimeConfig.configured()).thenReturn(true);
        when(systemInstanceInfo.timeZone()).thenReturn(ZoneId.of("UTC"));
        when(userPreferenceQuery.findValues(USER_ID, "notification")).thenReturn(Map.of(
                "emailNotification", Boolean.TRUE,
                "quietHours", Map.of("enabled", Boolean.TRUE, "start", "22:00", "end", "22:00")
        ));

        assertThat(service.shouldDeliver(USER_ID)).isTrue();
    }

    @Test
    void enqueueDeliveryWritesTaskRowAndOutboxInOneShot() {
        givenOptedInUser();

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
    void hourlyCapBlocksRegistrationAtAndAboveTheLimit() {
        givenOptedInUser();
        when(runtimeConfig.ratePerHour()).thenReturn(2);

        for (long recent : new long[] {2L, 3L}) {
            when(taskRecordService.countRecentTasks(
                    eq(NotificationEmailService.TASK_TYPE), eq(USER_ID), any(Instant.class)))
                    .thenReturn(recent);

            assertThat(service.enqueueDelivery(USER_ID, NOTIFICATION_ID))
                    .as("已登记 %d 条、上限 2 时不应再登记", recent)
                    .isEmpty();
        }

        verify(taskRecordService, never())
                .createQueuedTask(any(), any(), anyString(), anyString(), anyString(), anyString(), any(), any());
        verifyNoInteractions(taskDispatchService);
    }

    @Test
    void hourlyCapStillRegistersBelowTheLimit() {
        givenOptedInUser();
        when(runtimeConfig.ratePerHour()).thenReturn(2);
        when(taskRecordService.countRecentTasks(
                eq(NotificationEmailService.TASK_TYPE), eq(USER_ID), any(Instant.class)))
                .thenReturn(1L);

        assertThat(service.enqueueDelivery(USER_ID, NOTIFICATION_ID)).isPresent();
    }

    @Test
    void zeroCapMeansUnlimitedAndSkipsTheCountQuery() {
        givenOptedInUser();
        when(runtimeConfig.ratePerHour()).thenReturn(0);

        assertThat(service.enqueueDelivery(USER_ID, NOTIFICATION_ID)).isPresent();

        verify(taskRecordService, never()).countRecentTasks(anyString(), any(), any());
    }

    @Test
    void deliverSendsPlainTextByDefaultAndCompletesTask() {
        givenClaimed();
        when(notificationRepository.findByIdAndRecipientUserId(NOTIFICATION_ID, USER_ID))
                .thenReturn(Optional.of(notification("任务已完成", "备份任务在 3 秒内完成")));
        when(userAccountQuery.findDeliverableEmail(USER_ID)).thenReturn(Optional.of("alex@omninest.local"));
        when(notificationTypeRepository.findByTypeCode("TASK_COMPLETED"))
                .thenReturn(Optional.of(type("TASK_COMPLETED", "任务完成")));
        when(runtimeConfig.format()).thenReturn(MessageFormat.PLAIN);
        when(runtimeConfig.webBaseUrl()).thenReturn("");

        service.deliver(event());

        ArgumentCaptor<String> plain = ArgumentCaptor.forClass(String.class);
        verify(emailSender).send(eq("alex@omninest.local"), eq("任务已完成"), plain.capture(), eq(null));
        assertThat(plain.getValue())
                .contains("备份任务在 3 秒内完成")
                .contains("通知类型：任务完成");
        verify(taskRecordService).markCompleted(eq(TASK_ID), any(Map.class));
    }

    @Test
    void richFormatSendsHtmlWithEscapedUserData() {
        givenClaimed();
        when(notificationRepository.findByIdAndRecipientUserId(NOTIFICATION_ID, USER_ID)).thenReturn(Optional.of(
                notification("下载完成", "已导入 <b>movie.nfo</b> 与 </td></tr> 片段")));
        when(userAccountQuery.findDeliverableEmail(USER_ID)).thenReturn(Optional.of("alex@omninest.local"));
        when(notificationTypeRepository.findByTypeCode("TASK_COMPLETED"))
                .thenReturn(Optional.of(type("TASK_COMPLETED", "任务完成")));
        when(runtimeConfig.format()).thenReturn(MessageFormat.RICH);
        when(runtimeConfig.webBaseUrl()).thenReturn("https://nest.example.test");

        service.deliver(event());

        ArgumentCaptor<String> html = ArgumentCaptor.forClass(String.class);
        verify(emailSender).send(eq("alex@omninest.local"), eq("下载完成"), anyString(), html.capture());
        assertThat(html.getValue())
                .contains("&lt;b&gt;movie.nfo&lt;/b&gt;")
                .contains("&lt;/td&gt;&lt;/tr&gt;")
                .doesNotContain("<img")
                .contains("href=\"https://nest.example.test/#/notifications\"");
    }

    @Test
    void missingTitleFallsBackToTypeLabelAsSubject() {
        givenClaimed();
        when(notificationRepository.findByIdAndRecipientUserId(NOTIFICATION_ID, USER_ID))
                .thenReturn(Optional.of(notification("  ", "没有标题的正文")));
        when(userAccountQuery.findDeliverableEmail(USER_ID)).thenReturn(Optional.of("alex@omninest.local"));
        when(notificationTypeRepository.findByTypeCode("TASK_COMPLETED"))
                .thenReturn(Optional.of(type("TASK_COMPLETED", "任务完成")));
        when(runtimeConfig.format()).thenReturn(MessageFormat.PLAIN);
        when(runtimeConfig.webBaseUrl()).thenReturn("");

        service.deliver(event());

        verify(emailSender).send(anyString(), eq("任务完成"), anyString(), eq(null));
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
    void sendTestMailUsesTheSameRenderingPipeline() {
        when(notificationTypeRepository.findByTypeCode("SYSTEM_MESSAGE"))
                .thenReturn(Optional.of(type("SYSTEM_MESSAGE", "系统消息")));
        when(runtimeConfig.format()).thenReturn(MessageFormat.PLAIN);
        when(runtimeConfig.webBaseUrl()).thenReturn("");

        service.sendTestMail("ops@omninest.local");

        ArgumentCaptor<String> plain = ArgumentCaptor.forClass(String.class);
        verify(emailSender).send(eq("ops@omninest.local"), eq("OmniNest 邮件通道测试"), plain.capture(), eq(null));
        assertThat(plain.getValue()).contains("通知类型：系统消息");
    }

    private void givenOptedInUser() {
        when(runtimeConfig.configured()).thenReturn(true);
        when(userPreferenceQuery.findValues(USER_ID, "notification"))
                .thenReturn(Map.of("emailNotification", Boolean.TRUE));
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

    private NotificationType type(String code, String label) {
        NotificationType notificationType = new NotificationType();
        notificationType.setTypeCode(code);
        notificationType.setLabel(label);
        return notificationType;
    }
}
