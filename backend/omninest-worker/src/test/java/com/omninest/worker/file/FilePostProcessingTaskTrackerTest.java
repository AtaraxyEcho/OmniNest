package com.omninest.worker.file;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.file.event.FileUploadedEvent;
import com.omninest.modules.task.domain.TaskRecord;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import java.time.Instant;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;

/** 文件后处理任务跟踪器测试：领取、完成、失败重试与死信裁决。 */
class FilePostProcessingTaskTrackerTest {

    private TaskRecordService taskRecordService;
    private TaskDispatchService taskDispatchService;
    private FilePostProcessingTaskTracker tracker;

    private static final UUID OWNER = UUID.randomUUID();
    private static final UUID FILE_NODE = UUID.randomUUID();
    private static final UUID TASK = UUID.randomUUID();

    @BeforeEach
    void setUp() {
        taskRecordService = Mockito.mock(TaskRecordService.class);
        taskDispatchService = Mockito.mock(TaskDispatchService.class);
        tracker = new FilePostProcessingTaskTracker(taskRecordService, taskDispatchService);
    }

    private FileUploadedEvent event() {
        return new FileUploadedEvent(FILE_NODE, UUID.randomUUID(), OWNER, "bucket", "key",
                "a.jpg", "image/jpeg", 10, Instant.now());
    }

    private TaskRecord activeTask() {
        TaskRecord record = new TaskRecord();
        record.setId(TASK);
        record.setTaskType("THUMBNAIL");
        record.setStatus("QUEUED");
        return record;
    }

    @Test
    void beginClaimsActiveTask() {
        when(taskRecordService.findActiveResourceTask(
                eq(OWNER), eq("THUMBNAIL"), eq("FILE_NODE"), eq(FILE_NODE), any()))
                .thenReturn(Optional.of(activeTask()));
        when(taskRecordService.claimForExecution(TASK, "PROCESSING")).thenReturn(true);

        FilePostProcessingTaskTracker.TrackedTask tracked =
                tracker.begin(OWNER, "THUMBNAIL", FILE_NODE, "PROCESSING");

        org.junit.jupiter.api.Assertions.assertTrue(tracked.tracked());
        org.junit.jupiter.api.Assertions.assertFalse(tracked.shouldSkip());
    }

    @Test
    void beginReturnsUntrackedWhenNoTaskRecord() {
        when(taskRecordService.findActiveResourceTask(any(), anyString(), anyString(), any(), any()))
                .thenReturn(Optional.empty());

        FilePostProcessingTaskTracker.TrackedTask tracked =
                tracker.begin(OWNER, "FILE_INDEX", FILE_NODE, "INDEXING");

        org.junit.jupiter.api.Assertions.assertFalse(tracked.tracked());
        verify(taskRecordService, never()).claimForExecution(any(), anyString());
    }

    @Test
    void beginSignalsSkipWhenClaimFails() {
        when(taskRecordService.findActiveResourceTask(any(), anyString(), anyString(), any(), any()))
                .thenReturn(Optional.of(activeTask()));
        when(taskRecordService.claimForExecution(TASK, "PROCESSING")).thenReturn(false);

        FilePostProcessingTaskTracker.TrackedTask tracked =
                tracker.begin(OWNER, "THUMBNAIL", FILE_NODE, "PROCESSING");

        org.junit.jupiter.api.Assertions.assertTrue(tracked.shouldSkip());
    }

    @Test
    void completeIgnoresUntrackedTask() {
        assertDoesNotThrow(() -> tracker.complete(null, java.util.Map.of()));
        verify(taskRecordService, never()).markCompleted(any(), any());
    }

    @Test
    void failureEnqueuesDelayedRetryViaOutbox() {
        tracker.handleFailure("THUMBNAIL", QueueNames.THUMBNAIL_ROUTING_KEY, TASK, event(),
                new IllegalStateException("boom"));

        verify(taskRecordService).markRetryWait(eq(TASK), eq("IllegalStateException"), any());
        verify(taskDispatchService).enqueueAt(
                eq(TASK), eq(QueueNames.TASK_EXCHANGE), eq(QueueNames.THUMBNAIL_ROUTING_KEY),
                any(), any());
        verify(taskRecordService, never()).markDeadLetter(any(), anyString(), any());
    }

    @Test
    void failureMarksDeadLetterWhenRetriesExhausted() {
        when(taskRecordService.retryCount(TASK)).thenReturn(3);

        tracker.handleFailure("THUMBNAIL", QueueNames.THUMBNAIL_ROUTING_KEY, TASK, event(),
                new IllegalStateException("boom"));

        verify(taskRecordService).markDeadLetter(eq(TASK), anyString(), anyString());
        verify(taskDispatchService, never()).enqueueAt(any(), any(), any(), any(), any());
    }

    @Test
    void businessErrorGoesStraightToDeadLetter() {
        tracker.handleFailure("THUMBNAIL", QueueNames.THUMBNAIL_ROUTING_KEY, TASK, event(),
                new BusinessException(ErrorCode.FILE_NOT_FOUND, "missing"));

        verify(taskRecordService).markDeadLetter(eq(TASK), eq("FILE_NOT_FOUND"), anyString());
        verify(taskRecordService, never()).markRetryWait(any(), anyString(), any());
    }

    @Test
    void failureWithoutTaskRecordOnlyLogs() {
        assertDoesNotThrow(() -> tracker.handleFailure(
                "THUMBNAIL", QueueNames.THUMBNAIL_ROUTING_KEY, null, event(),
                new IllegalStateException("boom")));
        verify(taskRecordService, never()).markRetryWait(any(), anyString(), any());
        verify(taskRecordService, never()).markDeadLetter(any(), anyString(), any());
        verify(taskDispatchService, never()).enqueueAt(any(), any(), any(), any(), any());
    }
}
