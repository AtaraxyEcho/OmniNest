package com.omninest.modules.file.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyMap;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.file.event.FileUploadedEvent;
import com.omninest.modules.file.event.MediaAutoImportRequestedEvent;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import java.time.Instant;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;

/**
 * 文件上传后持久任务创建服务测试。
 *
 * @author OmniNest
 */
class FilePostProcessingTaskServiceTest {
    private final TaskRecordService taskRecordService = mock(TaskRecordService.class);
    private final TaskDispatchService taskDispatchService = mock(TaskDispatchService.class);
    private final FilePostProcessingTaskService service = new FilePostProcessingTaskService(
            taskRecordService,
            taskDispatchService
    );

    @Test
    void enqueueMediaAutoImportCreatesTaskAndOutbox() {
        FileUploadedEvent file = fileEvent();
        when(taskRecordService.findActiveResourceTask(
                eq(file.ownerUserId()),
                eq("MEDIA_AUTO_IMPORT"),
                eq("FILE_NODE"),
                eq(file.fileNodeId()),
                any()
        )).thenReturn(Optional.empty());

        UUID taskId = service.enqueueMediaAutoImport(file);

        assertThat(taskId).isNotNull();
        verify(taskRecordService).createQueuedTask(
                eq(taskId),
                eq(file.ownerUserId()),
                eq("MEDIA_AUTO_IMPORT"),
                eq(QueueNames.MEDIA_AUTO_IMPORT_ROUTING_KEY),
                eq("DETECTING"),
                eq("FILE_NODE"),
                eq(file.fileNodeId()),
                anyMap()
        );
        verify(taskDispatchService).enqueue(
                eq(taskId),
                eq(QueueNames.TASK_EXCHANGE),
                eq(QueueNames.MEDIA_AUTO_IMPORT_ROUTING_KEY),
                any(MediaAutoImportRequestedEvent.class)
        );
    }

    private FileUploadedEvent fileEvent() {
        return new FileUploadedEvent(
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
    }
}
