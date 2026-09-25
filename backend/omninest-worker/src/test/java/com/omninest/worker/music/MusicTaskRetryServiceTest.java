package com.omninest.worker.music;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.music.event.MusicScanEvent;
import com.omninest.modules.task.service.StaleTaskRecovery;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import java.time.Instant;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.junit.jupiter.api.extension.ExtendWith;

/**
 * 音乐任务重试服务单元测试。
 *
 * @author OmniNest
 */
@ExtendWith(MockitoExtension.class)
class MusicTaskRetryServiceTest {
    private static final UUID TASK_ID = UUID.fromString("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
    private static final UUID OWNER_ID = UUID.fromString("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");

    @Mock
    private TaskRecordService taskRecordService;

    @Mock
    private TaskDispatchService taskDispatchService;

    @Test
    void transientScanFailureIsDelayedAndRepublished() {
        MusicTaskRetryService service = new MusicTaskRetryService(taskRecordService, taskDispatchService);
        MusicScanEvent event = new MusicScanEvent(TASK_ID, OWNER_ID);
        when(taskRecordService.retryCount(TASK_ID)).thenReturn(0);
        when(taskRecordService.markRetryWait(eq(TASK_ID), anyString(), any(Instant.class))).thenReturn(1);

        service.handleScanFailure(event, new IllegalStateException("network"));

        verify(taskRecordService).markRetryWait(eq(TASK_ID), eq("IllegalStateException"), any(Instant.class));
        verify(taskDispatchService).enqueueAt(
                eq(TASK_ID),
                eq(QueueNames.TASK_EXCHANGE),
                eq(QueueNames.MUSIC_SCAN_ROUTING_KEY),
                eq(event),
                any(Instant.class)
        );
    }

    @Test
    void fourthFailureMovesTaskToDeadLetterWithoutRepublish() {
        MusicTaskRetryService service = new MusicTaskRetryService(taskRecordService, taskDispatchService);
        when(taskRecordService.retryCount(TASK_ID)).thenReturn(3);

        service.handleScanFailure(
                new MusicScanEvent(TASK_ID, OWNER_ID),
                new IllegalStateException("network")
        );

        verify(taskRecordService).markDeadLetter(eq(TASK_ID), eq("IllegalStateException"), anyString());
        verify(taskDispatchService, never()).enqueueAt(any(), anyString(), anyString(), any(), any());
    }

    @Test
    void staleScanTaskIsRequeuedFromPersistedPayload() {
        MusicTaskRetryService service = new MusicTaskRetryService(taskRecordService, taskDispatchService);
        Instant cutoff = Instant.parse("2026-08-17T08:00:00Z");
        Instant nextRetryAt = cutoff.plusSeconds(60);
        when(taskRecordService.taskPayload(TASK_ID)).thenReturn(Map.of(
                "jobId", TASK_ID.toString(),
                "ownerUserId", OWNER_ID.toString()
        ));
        when(taskRecordService.recoverStaleTask(
                eq(TASK_ID), eq("MUSIC_SCAN"), eq(cutoff), any(Instant.class), eq("WORKER_HEARTBEAT_TIMEOUT")
        )).thenReturn(new StaleTaskRecovery(true, false, OWNER_ID, TASK_ID, 1, nextRetryAt));

        service.recoverStaleScanTask(TASK_ID, cutoff);

        verify(taskDispatchService).enqueueAt(
                eq(TASK_ID),
                eq(QueueNames.TASK_EXCHANGE),
                eq(QueueNames.MUSIC_SCAN_ROUTING_KEY),
                eq(new MusicScanEvent(TASK_ID, OWNER_ID)),
                eq(nextRetryAt)
        );
        assertThat(nextRetryAt).isAfter(cutoff);
    }
}
