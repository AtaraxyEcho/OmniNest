package com.omninest.worker.notification;

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
import com.omninest.modules.notification.event.NotificationEmailRequestedEvent;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import java.time.Duration;
import java.time.Instant;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

/**
 * 邮件投递失败的退避阶梯与死信终态。
 *
 * @author OmniNest
 */
class NotificationEmailRetryServiceTest {

    private static final UUID TASK_ID = UUID.fromString("70000000-0000-0000-0000-000000000001");
    private static final UUID USER_ID = UUID.fromString("70000000-0000-0000-0000-000000000002");
    private static final UUID NOTIFICATION_ID = UUID.fromString("70000000-0000-0000-0000-000000000003");

    private final TaskRecordService taskRecordService = mock(TaskRecordService.class);
    private final TaskDispatchService taskDispatchService = mock(TaskDispatchService.class);
    private final NotificationEmailRetryService retryService =
            new NotificationEmailRetryService(taskRecordService, taskDispatchService);

    @Test
    void firstFailureWaitsOneMinuteAndCreatesDelayedOutbox() {
        when(taskRecordService.retryCount(TASK_ID)).thenReturn(0);
        NotificationEmailRequestedEvent event = event();

        retryService.handleFailure(event, new IllegalStateException("smtp down"));

        ArgumentCaptor<Instant> nextRetryAt = ArgumentCaptor.forClass(Instant.class);
        verify(taskRecordService).markRetryWait(eq(TASK_ID), eq("IllegalStateException"), nextRetryAt.capture());
        assertThat(Duration.between(Instant.now(), nextRetryAt.getValue())).isBetween(
                Duration.ofSeconds(50),
                Duration.ofSeconds(70)
        );
        verify(taskDispatchService).enqueueAt(
                eq(TASK_ID),
                eq(QueueNames.TASK_EXCHANGE),
                eq(QueueNames.NOTIFICATION_EMAIL_ROUTING_KEY),
                eq(event),
                eq(nextRetryAt.getValue())
        );
        verify(taskRecordService, never()).markDeadLetter(any(), anyString(), anyString());
    }

    @Test
    void thirdFailureWaitsFifteenMinutes() {
        when(taskRecordService.retryCount(TASK_ID)).thenReturn(2);

        retryService.handleFailure(event(), new IllegalStateException("smtp down"));

        ArgumentCaptor<Instant> nextRetryAt = ArgumentCaptor.forClass(Instant.class);
        verify(taskRecordService).markRetryWait(eq(TASK_ID), anyString(), nextRetryAt.capture());
        assertThat(Duration.between(Instant.now(), nextRetryAt.getValue())).isBetween(
                Duration.ofSeconds(860),
                Duration.ofSeconds(910)
        );
    }

    @Test
    void exhaustedRetriesGoToDeadLetterWithoutOutbox() {
        when(taskRecordService.retryCount(TASK_ID)).thenReturn(3);

        retryService.handleFailure(event(), new IllegalStateException("smtp down"));

        verify(taskRecordService).markDeadLetter(eq(TASK_ID), eq("IllegalStateException"), anyString());
        verifyNoInteractions(taskDispatchService);
        verify(taskRecordService, never()).markRetryWait(any(), anyString(), any(Instant.class));
    }

    private NotificationEmailRequestedEvent event() {
        return new NotificationEmailRequestedEvent(TASK_ID, USER_ID, NOTIFICATION_ID);
    }
}
