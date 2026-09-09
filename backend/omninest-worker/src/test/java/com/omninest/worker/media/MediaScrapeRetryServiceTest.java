package com.omninest.worker.media;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import com.omninest.modules.video.event.MediaScrapeRequestedEvent;
import java.time.Duration;
import java.time.Instant;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.Mockito;

/**
 * 媒体刮削重试服务测试：验证退避重投与死信终态裁决。
 *
 * @author OmniNest
 */
class MediaScrapeRetryServiceTest {

    private static final UUID TASK_ID = UUID.fromString("40000000-0000-0000-0000-000000000001");
    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID FILE_ID = UUID.fromString("30000000-0000-0000-0000-000000000001");

    private final TaskRecordService taskRecordService = Mockito.mock(TaskRecordService.class);
    private final TaskDispatchService taskDispatchService = Mockito.mock(TaskDispatchService.class);
    private final MediaScrapeRetryService retryService =
            new MediaScrapeRetryService(taskRecordService, taskDispatchService);

    @Test
    void schedulesDelayedRedispatchThroughOutbox() {
        MediaScrapeRequestedEvent event = event();
        when(taskRecordService.retryCount(TASK_ID)).thenReturn(0);
        when(taskRecordService.markRetryWait(eq(TASK_ID), any(), any())).thenReturn(1);
        Instant invocationStart = Instant.now();

        retryService.handleFailure(event, new IllegalStateException("provider unavailable"));

        ArgumentCaptor<Instant> nextRetryAt = ArgumentCaptor.forClass(Instant.class);
        verify(taskRecordService).markRetryWait(eq(TASK_ID), eq("IllegalStateException"), nextRetryAt.capture());
        assertThat(Duration.between(invocationStart, nextRetryAt.getValue()))
                .isBetween(Duration.ofSeconds(59), Duration.ofSeconds(90));
        verify(taskDispatchService).enqueueAt(
                eq(TASK_ID),
                eq(QueueNames.TASK_EXCHANGE),
                eq(QueueNames.MEDIA_SCRAPE_ROUTING_KEY),
                eq(event),
                eq(nextRetryAt.getValue())
        );
        verify(taskRecordService, never()).markDeadLetter(eq(TASK_ID), any());
    }

    @Test
    void marksDeadLetterWhenRetriesExhausted() {
        MediaScrapeRequestedEvent event = event();
        when(taskRecordService.retryCount(TASK_ID)).thenReturn(3);

        retryService.handleFailure(event, new IllegalStateException("provider unavailable"));

        verify(taskRecordService).markDeadLetter(eq(TASK_ID), any());
        verify(taskRecordService, never()).markRetryWait(eq(TASK_ID), any(), any());
        verify(taskDispatchService, never()).enqueueAt(any(), any(), any(), any(), any());
    }

    private MediaScrapeRequestedEvent event() {
        return new MediaScrapeRequestedEvent(
                TASK_ID,
                OWNER_ID,
                FILE_ID,
                "测试影片",
                2026,
                null,
                null,
                false
        );
    }
}
