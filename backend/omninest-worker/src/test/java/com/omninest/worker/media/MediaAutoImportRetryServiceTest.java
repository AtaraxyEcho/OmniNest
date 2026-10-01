package com.omninest.worker.media;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyMap;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.omninest.modules.file.event.FileUploadedEvent;
import com.omninest.modules.file.event.MediaAutoImportRequestedEvent;
import com.omninest.modules.notification.port.NotificationPublisher;
import com.omninest.modules.task.service.StaleTaskRecovery;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import java.time.Instant;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;

/**
 * 媒体自动导入失败重试服务测试。
 *
 * @author OmniNest
 */
class MediaAutoImportRetryServiceTest {
    private final TaskRecordService taskRecordService = mock(TaskRecordService.class);
    private final TaskDispatchService taskDispatchService = mock(TaskDispatchService.class);
    private final NotificationPublisher notificationPublisher = mock(NotificationPublisher.class);
    private final MediaAutoImportRetryService service = new MediaAutoImportRetryService(
            taskRecordService,
            taskDispatchService,
            notificationPublisher
    );

    @Test
    void deadLetterTerminalPublishesFailureNotification() {
        MediaAutoImportRequestedEvent event = event();
        when(taskRecordService.retryCount(event.taskId())).thenReturn(3);

        service.handleFailure(event, new IllegalStateException("导入失败"));

        verify(taskRecordService).markDeadLetter(eq(event.taskId()), any(), any());
        // 死信终态必须通知用户，避免导入失败无感知。
        verify(notificationPublisher).notifyOrLog(
                eq(event.file().ownerUserId()),
                eq("MEDIA_AUTO_IMPORT_FAILED"),
                isNull(),
                isNull(),
                eq(Map.of(
                        "taskId", event.taskId().toString(),
                        "fileNodeId", event.file().fileNodeId().toString(),
                        "fileName", "example.mp4",
                        "errorSummary", "IllegalStateException"
                ))
        );
        verifyNoInteractions(taskDispatchService);
    }

    @Test
    void retryWaitDoesNotPublishNotification() {
        MediaAutoImportRequestedEvent event = event();
        when(taskRecordService.retryCount(event.taskId())).thenReturn(1);

        service.handleFailure(event, new IllegalStateException("导入失败"));

        verify(taskRecordService).markRetryWait(eq(event.taskId()), any(), any());
        verify(taskDispatchService).enqueueAt(
                eq(event.taskId()),
                any(),
                any(),
                eq(event),
                any()
        );
        verify(notificationPublisher, never()).notifyOrLog(any(), any(), any(), any(), anyMap());
    }

    @Test
    void recoverStaleDeadLetterPublishesFailureNotification() {
        UUID taskId = UUID.randomUUID();
        UUID ownerId = UUID.randomUUID();
        when(taskRecordService.taskPayload(taskId)).thenReturn(Map.of(
                "fileObjectId", UUID.randomUUID().toString(),
                "fileName", "example.mp4",
                "mimeType", "video/mp4",
                "sizeBytes", 1024L
        ));
        when(taskRecordService.recoverStaleTask(eq(taskId), eq("MEDIA_AUTO_IMPORT"), any(), any(), any()))
                .thenReturn(new StaleTaskRecovery(
                        true,
                        true,
                        ownerId,
                        UUID.randomUUID(),
                        3,
                        null
                ));

        service.recoverStaleTask(taskId, Instant.now());

        verify(notificationPublisher).notifyOrLog(
                eq(ownerId),
                eq("MEDIA_AUTO_IMPORT_FAILED"),
                isNull(),
                isNull(),
                eq(Map.of(
                        "taskId", taskId.toString(),
                        "fileName", "example.mp4",
                        "errorCode", "WORKER_HEARTBEAT_TIMEOUT"
                ))
        );
    }

    @Test
    void recoverStaleRequeueDoesNotPublishNotification() {
        UUID taskId = UUID.randomUUID();
        UUID ownerId = UUID.randomUUID();
        when(taskRecordService.taskPayload(taskId)).thenReturn(Map.of(
                "fileObjectId", UUID.randomUUID().toString(),
                "fileName", "example.mp4",
                "mimeType", "video/mp4",
                "sizeBytes", 1024L
        ));
        when(taskRecordService.recoverStaleTask(eq(taskId), eq("MEDIA_AUTO_IMPORT"), any(), any(), any()))
                .thenReturn(new StaleTaskRecovery(
                        true,
                        false,
                        ownerId,
                        UUID.randomUUID(),
                        1,
                        Instant.now().plusSeconds(60)
                ));

        service.recoverStaleTask(taskId, Instant.now());

        verify(taskDispatchService).enqueueAt(eq(taskId), any(), any(), any(), any());
        verify(notificationPublisher, never()).notifyOrLog(any(), any(), any(), any(), anyMap());
    }

    private MediaAutoImportRequestedEvent event() {
        FileUploadedEvent file = new FileUploadedEvent(
                UUID.randomUUID(),
                UUID.randomUUID(),
                UUID.randomUUID(),
                "user-files",
                "files/example.mp4",
                "example.mp4",
                "video/mp4",
                1024L,
                Instant.now()
        );
        return new MediaAutoImportRequestedEvent(UUID.randomUUID(), file);
    }
}
