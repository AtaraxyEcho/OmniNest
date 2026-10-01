package com.omninest.worker.media;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyMap;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.dto.FileDescriptor;
import com.omninest.modules.file.event.FileUploadedEvent;
import com.omninest.modules.file.event.MediaAutoImportRequestedEvent;
import com.omninest.modules.file.service.FileLifecycleGuard;
import com.omninest.modules.media.service.MediaImportHandler;
import com.omninest.modules.media.service.MediaImportResult;
import com.omninest.modules.notification.port.NotificationPublisher;
import com.omninest.modules.task.service.TaskRecordService;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;

/**
 * 媒体自动导入任务执行服务测试。
 *
 * @author OmniNest
 */
class MediaAutoImportExecutionServiceTest {
    private final MediaImportHandler supportedHandler = mock(MediaImportHandler.class);
    private final MediaImportHandler skippedHandler = mock(MediaImportHandler.class);
    private final TaskRecordService taskRecordService = mock(TaskRecordService.class);
    private final FileLifecycleGuard fileLifecycleGuard = mock(FileLifecycleGuard.class);
    private final NotificationPublisher notificationPublisher = mock(NotificationPublisher.class);
    private final MediaAutoImportExecutionService service = new MediaAutoImportExecutionService(
            List.of(supportedHandler, skippedHandler),
            taskRecordService,
            fileLifecycleGuard,
            notificationPublisher
    );

    @Test
    void executePersistsHandlerResultsAndCompletesTask() {
        MediaAutoImportRequestedEvent event = event();
        FileDescriptor descriptor = descriptor(SpaceType.PERSONAL);
        when(taskRecordService.claimForExecution(event.taskId(), "DETECTING")).thenReturn(true);
        when(fileLifecycleGuard.requireOwnedWritable(
                event.file().ownerUserId(),
                event.file().fileNodeId()
        )).thenReturn(descriptor);
        when(supportedHandler.module()).thenReturn("PHOTOS");
        when(supportedHandler.supports(event.file())).thenReturn(true);
        when(supportedHandler.importFile(event.file()))
                .thenReturn(new MediaImportResult("PHOTOS", event.file().fileNodeId()));
        when(skippedHandler.module()).thenReturn("MUSIC");
        when(skippedHandler.supports(event.file())).thenReturn(false);

        service.execute(event);

        verify(supportedHandler).importFile(event.file());
        verify(skippedHandler, never()).importFile(event.file());
        verify(taskRecordService).markCompleted(eq(event.taskId()), anyMap());
        // 终态完成必须发站内通知；文案由前端本地化，后端只落语义载荷。
        verify(notificationPublisher).notifyOrLog(
                eq(event.file().ownerUserId()),
                eq("MEDIA_AUTO_IMPORT_COMPLETED"),
                isNull(),
                isNull(),
                eq(Map.of(
                        "taskId", event.taskId().toString(),
                        "fileNodeId", event.file().fileNodeId().toString(),
                        "fileName", "example.jpg"
                ))
        );
    }

    @Test
    void executePersistsFailureBeforePropagatingException() {
        MediaAutoImportRequestedEvent event = event();
        FileDescriptor descriptor = descriptor(SpaceType.PERSONAL);
        when(taskRecordService.claimForExecution(event.taskId(), "DETECTING")).thenReturn(true);
        when(fileLifecycleGuard.requireOwnedWritable(
                event.file().ownerUserId(),
                event.file().fileNodeId()
        )).thenReturn(descriptor);
        when(supportedHandler.module()).thenReturn("PHOTOS");
        when(supportedHandler.supports(event.file())).thenReturn(true);
        when(supportedHandler.importFile(event.file())).thenThrow(new IllegalStateException("导入失败"));

        assertThatThrownBy(() -> service.execute(event)).isInstanceOf(IllegalStateException.class);

        verify(taskRecordService).updateResult(eq(event.taskId()), anyMap());
        verify(taskRecordService, never()).markCompleted(eq(event.taskId()), anyMap());
        // 非终态失败不发通知，由重试服务在死信终态统一通知。
        verify(notificationPublisher, never()).notifyOrLog(
                any(),
                any(),
                any(),
                any(),
                anyMap()
        );
    }

    private FileDescriptor descriptor(SpaceType spaceType) {
        FileDescriptor descriptor = mock(FileDescriptor.class);
        when(descriptor.spaceType()).thenReturn(spaceType);
        return descriptor;
    }

    private MediaAutoImportRequestedEvent event() {
        FileUploadedEvent file = new FileUploadedEvent(
                UUID.randomUUID(),
                UUID.randomUUID(),
                UUID.randomUUID(),
                "user-files",
                "files/example.jpg",
                "example.jpg",
                "image/jpeg",
                1024L,
                Instant.now()
        );
        return new MediaAutoImportRequestedEvent(UUID.randomUUID(), file);
    }
}
