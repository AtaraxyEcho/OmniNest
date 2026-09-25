package com.omninest.worker.reader;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.modules.notification.port.NotificationPublisher;
import com.omninest.modules.reader.event.ComicParseTaskEvent;
import com.omninest.modules.reader.service.ReaderComicManifestService;
import com.omninest.modules.task.service.StaleTaskRecovery;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import java.time.Instant;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

/**
 * 漫画解析重试服务单元测试。
 *
 * @author OmniNest
 */
@ExtendWith(MockitoExtension.class)
class ComicParseRetryServiceTest {

    private static final UUID TASK_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000002");
    private static final UUID ITEM_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");
    private static final UUID SOURCE_ID = UUID.fromString("30000000-0000-0000-0000-000000000001");
    private static final UUID FILE_NODE_ID = UUID.fromString("40000000-0000-0000-0000-000000000001");

    @Mock
    private TaskRecordService taskRecordService;
    @Mock
    private TaskDispatchService taskDispatchService;
    @Mock
    private ReaderComicManifestService manifestService;
    @Mock
    private NotificationPublisher notificationPublisher;

    @InjectMocks
    private ComicParseRetryService retryService;

    @Test
    void retriesInfrastructureFailureBeforeLimit() {
        when(taskRecordService.retryCount(TASK_ID)).thenReturn(1);

        retryService.handleFailure(event(false), new IllegalStateException("storage unavailable"));

        verify(taskRecordService).markRetryWait(eq(TASK_ID), eq("IllegalStateException"), any(Instant.class));
        verify(taskDispatchService).enqueueAt(eq(TASK_ID), anyString(), anyString(), any(), any(Instant.class));
        verify(manifestService, never()).markSourceFailed(any(), any(), anyString(), anyString());
    }

    @Test
    void marksSourceFailedWhenRetriesAreExhausted() {
        when(taskRecordService.retryCount(TASK_ID)).thenReturn(3);
        when(taskRecordService.markDeadLetter(eq(TASK_ID), eq("IllegalStateException"), any())).thenReturn(true);

        retryService.handleFailure(event(true), new IllegalStateException("storage unavailable"));

        verify(taskRecordService).markDeadLetter(eq(TASK_ID), eq("IllegalStateException"), anyString());
        verify(manifestService).markSourceFailed(
                eq(ITEM_ID),
                eq(SOURCE_ID),
                eq("COMIC_PARSE_FAILED"),
                anyString()
        );
        verify(notificationPublisher).notifyOrLog(
                eq(OWNER_ID),
                eq("TASK_FAILED"),
                eq("漫画解析失败"),
                anyString(),
                any()
        );
        verify(taskDispatchService, never()).enqueueAt(any(), anyString(), anyString(), any(), any());
    }

    @Test
    void duplicateTerminalDeliveryDoesNotNotifyAgain() {
        when(taskRecordService.retryCount(TASK_ID)).thenReturn(3);
        when(taskRecordService.markDeadLetter(eq(TASK_ID), eq("IllegalStateException"), any())).thenReturn(false);

        retryService.handleFailure(event(true), new IllegalStateException("storage unavailable"));

        verify(manifestService, never()).markSourceFailed(any(), any(), anyString(), anyString());
        verify(notificationPublisher, never()).notifyOrLog(any(), anyString(), anyString(), anyString(), any());
    }

    @Test
    void recoversStaleRunningTaskFromPersistedPayload() {
        Instant cutoff = Instant.now().minusSeconds(120);
        Instant nextRetryAt = Instant.now().plusSeconds(60);
        when(taskRecordService.taskPayload(TASK_ID)).thenReturn(payload());
        when(taskRecordService.recoverStaleTask(
                eq(TASK_ID),
                eq("COMIC_PARSE"),
                eq(cutoff),
                any(Instant.class),
                eq("WORKER_HEARTBEAT_TIMEOUT")
        )).thenReturn(new StaleTaskRecovery(true, false, OWNER_ID, FILE_NODE_ID, 1, nextRetryAt));

        retryService.recoverStaleTask(TASK_ID, cutoff);

        verify(taskDispatchService).enqueueAt(
                eq(TASK_ID),
                anyString(),
                anyString(),
                eq(event(true)),
                eq(nextRetryAt)
        );
    }

    private ComicParseTaskEvent event(boolean retry) {
        return new ComicParseTaskEvent(
                TASK_ID,
                OWNER_ID,
                ITEM_ID,
                SOURCE_ID,
                FILE_NODE_ID,
                "EPUB",
                "hash",
                retry
        );
    }

    private Map<String, Object> payload() {
        return Map.of(
                "ownerUserId", OWNER_ID.toString(),
                "itemId", ITEM_ID.toString(),
                "sourceId", SOURCE_ID.toString(),
                "fileNodeId", FILE_NODE_ID.toString(),
                "fileFormat", "EPUB",
                "contentHash", "hash"
        );
    }
}
