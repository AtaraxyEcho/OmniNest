package com.omninest.worker.reader;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.modules.notification.port.NotificationPublisher;
import com.omninest.modules.reader.event.ReaderParseTaskEvent;
import com.omninest.modules.reader.service.ReaderTextManifestService;
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
 * 文本书籍解析重试服务单元测试，验证重试耗尽进 DLQ 时回写条目失败状态。
 *
 * @author OmniNest
 */
@ExtendWith(MockitoExtension.class)
class ReaderTextParseRetryServiceTest {

    private static final UUID TASK_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000002");
    private static final UUID ITEM_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");
    private static final UUID FILE_NODE_ID = UUID.fromString("30000000-0000-0000-0000-000000000001");

    @Mock
    private TaskRecordService taskRecordService;
    @Mock
    private TaskDispatchService taskDispatchService;
    @Mock
    private ReaderTextManifestService manifestService;
    @Mock
    private NotificationPublisher notificationPublisher;

    @InjectMocks
    private ReaderTextParseRetryService retryService;

    private ReaderParseTaskEvent event(boolean retry) {
        return new ReaderParseTaskEvent(
                TASK_ID,
                OWNER_ID,
                ITEM_ID,
                FILE_NODE_ID,
                "EPUB",
                "hash",
                retry
        );
    }

    @Test
    void retriesBeforeMaxKeepItemParsing() {
        when(taskRecordService.retryCount(TASK_ID)).thenReturn(2);
        when(taskRecordService.markRetryWait(eq(TASK_ID), anyString(), any()))
                .thenReturn(1);

        retryService.handleFailure(event(false), new RuntimeException("boom"));

        verify(taskRecordService, never()).markDeadLetter(eq(TASK_ID), anyString(), any());
        verify(manifestService, never()).markFailed(any(), any(), any());
        verify(taskDispatchService).enqueueAt(
                eq(TASK_ID), any(), any(), any(), any());
    }

    @Test
    void maxRetriesMarksItemFailedAndDeadLetter() {
        when(taskRecordService.retryCount(TASK_ID)).thenReturn(3);
        when(taskRecordService.markDeadLetter(eq(TASK_ID), anyString(), any())).thenReturn(true);

        retryService.handleFailure(event(false), new RuntimeException("boom"));

        verify(taskRecordService).markDeadLetter(eq(TASK_ID), anyString(), anyString());
        verify(manifestService).markFailed(
                eq(ITEM_ID),
                eq("READER_PARSE_FAILED"),
                anyString()
        );
        verify(notificationPublisher).notifyOrLog(
                eq(OWNER_ID),
                eq("TASK_FAILED"),
                eq("书籍解析失败"),
                anyString(),
                any()
        );
        verify(taskDispatchService, never()).enqueueAt(
                any(), any(), any(), any(), any());
    }

    @Test
    void staleTaskExhaustionMarksItemFailed() {
        Instant cutoff = Instant.now().minusSeconds(120);
        when(taskRecordService.taskPayload(TASK_ID)).thenReturn(Map.of(
                "ownerUserId", OWNER_ID.toString(),
                "itemId", ITEM_ID.toString(),
                "fileNodeId", FILE_NODE_ID.toString(),
                "fileFormat", "EPUB",
                "contentHash", "hash"
        ));
        when(taskRecordService.recoverStaleTask(
                eq(TASK_ID),
                eq("READER_PARSE"),
                eq(cutoff),
                any(Instant.class),
                eq("WORKER_HEARTBEAT_TIMEOUT")
        )).thenReturn(new StaleTaskRecovery(true, true, OWNER_ID, ITEM_ID, 3, null));

        retryService.recoverStaleTask(TASK_ID, cutoff);

        verify(manifestService).markFailed(
                ITEM_ID,
                "READER_PARSE_FAILED",
                "文本书籍解析失败，已进入死信队列: WORKER_HEARTBEAT_TIMEOUT"
        );
        verify(notificationPublisher).notifyOrLog(
                eq(OWNER_ID),
                eq("TASK_FAILED"),
                eq("书籍解析失败"),
                anyString(),
                any()
        );
        verify(taskDispatchService, never()).enqueueAt(any(), any(), any(), any(), any());
    }
}
