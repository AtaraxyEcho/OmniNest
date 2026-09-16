package com.omninest.worker.task;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.modules.task.domain.TaskDispatch;
import com.omninest.modules.task.domain.TaskRecord;
import com.omninest.modules.task.repository.TaskDispatchRepository;
import com.omninest.modules.task.service.StaleTaskRecovery;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import com.omninest.modules.task.service.TaskRedispatchService;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
import org.springframework.test.util.ReflectionTestUtils;

/** 通用恢复调度器测试：心跳重投经 Outbox 退避、死信裁决与停滞任务清扫。 */
class GenericTaskRecoverySchedulerTest {

    private TaskRecordService taskRecordService;
    private TaskDispatchRepository taskDispatchRepository;
    private TaskDispatchService taskDispatchService;
    private TaskRedispatchService taskRedispatchService;
    private GenericTaskRecoveryScheduler scheduler;

    private static final UUID TASK = UUID.randomUUID();
    private static final Instant CUTOFF = Instant.now().minusSeconds(600);
    private static final Instant NEXT_RETRY = Instant.now().plusSeconds(60);

    @BeforeEach
    void setUp() {
        taskRecordService = Mockito.mock(TaskRecordService.class);
        taskDispatchRepository = Mockito.mock(TaskDispatchRepository.class);
        taskDispatchService = Mockito.mock(TaskDispatchService.class);
        taskRedispatchService = Mockito.mock(TaskRedispatchService.class);
        scheduler = new GenericTaskRecoveryScheduler(
                taskRecordService, taskDispatchRepository, taskDispatchService, taskRedispatchService);
        ReflectionTestUtils.setField(scheduler, "staleHeartbeatSeconds", 600L);
        ReflectionTestUtils.setField(scheduler, "stuckDispatchSeconds", 1800L);
    }

    private TaskDispatch dispatch() {
        TaskDispatch dispatch = new TaskDispatch();
        dispatch.setTaskId(TASK);
        dispatch.setExchangeName("omni.task");
        dispatch.setRoutingKey("thumbnail.generate");
        dispatch.setPayload("{\"fileNodeId\":\"1\"}");
        dispatch.setStatus("PUBLISHED");
        return dispatch;
    }

    private TaskRecord stuckRecord(String status) {
        TaskRecord record = new TaskRecord();
        record.setId(TASK);
        record.setTaskType("MEDIA_SCRAPE");
        record.setStatus(status);
        record.setRoutingKey("media.scrape");
        record.setPayload("{\"taskId\":\"" + TASK + "\"}");
        record.setCreatedAt(Instant.now().minusSeconds(3600));
        return record;
    }

    @Test
    void republishesOriginalMessageThroughOutboxWithBackoff() {
        when(taskRecordService.listStaleRunningTaskIds(eq("THUMBNAIL"), any(), org.mockito.ArgumentMatchers.anyInt()))
                .thenReturn(List.of(TASK));
        when(taskRecordService.recoverStaleTask(
                eq(TASK), eq("THUMBNAIL"), any(), any(), anyString()))
                .thenReturn(new StaleTaskRecovery(true, false, null, null, 1, NEXT_RETRY));
        when(taskDispatchRepository.findFirstByTaskIdOrderByCreatedAtDesc(TASK))
                .thenReturn(Optional.of(dispatch()));

        scheduler.recoverStaleTasks();

        // 重试状态与退避由 recoverStaleTask 单点完成，恢复重投不得重复计数。
        verify(taskRecordService, never()).markRetryWait(any(), anyString(), any());
        verify(taskDispatchService).enqueueAt(
                eq(TASK), eq("omni.task"), eq("thumbnail.generate"), any(), eq(NEXT_RETRY));
    }

    @Test
    void deadLettersTaskWhenRepublishFails() {
        when(taskRecordService.listStaleRunningTaskIds(eq("THUMBNAIL"), any(), org.mockito.ArgumentMatchers.anyInt()))
                .thenReturn(List.of(TASK));
        when(taskRecordService.recoverStaleTask(
                eq(TASK), eq("THUMBNAIL"), any(), any(), anyString()))
                .thenReturn(new StaleTaskRecovery(true, false, null, null, 1, NEXT_RETRY));
        when(taskDispatchRepository.findFirstByTaskIdOrderByCreatedAtDesc(TASK))
                .thenReturn(Optional.of(dispatch()));
        Mockito.doThrow(new IllegalStateException("broker down"))
                .when(taskDispatchService)
                .enqueueAt(eq(TASK), anyString(), anyString(), any(), eq(NEXT_RETRY));

        scheduler.recoverStaleTasks();

        verify(taskRecordService).markDeadLetter(
                eq(TASK), eq("WORKER_HEARTBEAT_TIMEOUT:REDISPATCH_FAILED"));
    }

    @Test
    void deadLetterWhenRetriesExhausted() {
        when(taskRecordService.listStaleRunningTaskIds(eq("THUMBNAIL"), any(), org.mockito.ArgumentMatchers.anyInt()))
                .thenReturn(List.of(TASK));
        when(taskRecordService.recoverStaleTask(
                eq(TASK), eq("THUMBNAIL"), any(), any(), anyString()))
                .thenReturn(new StaleTaskRecovery(true, true, null, null, 3, null));

        scheduler.recoverStaleTasks();

        verify(taskDispatchService, never()).enqueueAt(any(), any(), any(), any(), any());
        verify(taskRecordService, never()).markRetryWait(any(), anyString(), any());
    }

    @Test
    void deadLetterWhenOutboxMissing() {
        when(taskRecordService.listStaleRunningTaskIds(eq("PHOTO_SCAN"), any(), org.mockito.ArgumentMatchers.anyInt()))
                .thenReturn(List.of(TASK));
        when(taskRecordService.recoverStaleTask(
                eq(TASK), eq("PHOTO_SCAN"), any(), any(), anyString()))
                .thenReturn(new StaleTaskRecovery(true, false, null, null, 1, NEXT_RETRY));
        when(taskDispatchRepository.findFirstByTaskIdOrderByCreatedAtDesc(TASK))
                .thenReturn(Optional.empty());

        scheduler.recoverStaleTasks();

        verify(taskRecordService).markDeadLetter(eq(TASK), eq("WORKER_HEARTBEAT_TIMEOUT:OUTBOX_MISSING"));
        verify(taskDispatchService, never()).enqueueAt(any(), any(), any(), any(), any());
    }

    @Test
    void onlyConfiguredTaskTypesAreScanned() {
        when(taskRecordService.listStaleRunningTaskIds(anyString(), any(), org.mockito.ArgumentMatchers.anyInt()))
                .thenReturn(List.of());

        scheduler.recoverStaleTasks();

        for (String taskType : List.of("PHOTO_SCAN", "PHOTO_THUMBNAILS", "PHOTO_BATCH",
                "PHOTO_MOTION", "PHOTO_MOTION_RESCAN", "EXTERNAL_IMPORT",
                "OFFLINE_DOWNLOAD", "MEDIA_SCRAPE", "VIDEO_TRANSCODE", "WEB_OPTIMIZE",
                "AUDIO_EXTRACT", "FILE_INDEX", "THUMBNAIL", "TEXT_EXTRACTION",
                "LOCAL_VIDEO_LIBRARY_DISCOVERY", "LOCAL_VIDEO_LIBRARY_APPLY")) {
            verify(taskRecordService).listStaleRunningTaskIds(eq(taskType), any(), org.mockito.ArgumentMatchers.anyInt());
        }
        // 专用恢复调度器已覆盖的类型不在通用调度器范围内。
        verify(taskRecordService, never()).listStaleRunningTaskIds(eq("PHOTO_AI"), any(), org.mockito.ArgumentMatchers.anyInt());
        verify(taskRecordService, never()).listStaleRunningTaskIds(eq("PHOTO_GEO_IMPORT"), any(), org.mockito.ArgumentMatchers.anyInt());
    }

    @Test
    void sweepRedispatchesStuckTaskWithoutDispatch() {
        TaskRecord record = stuckRecord("QUEUED");
        when(taskRecordService.listStuckTasks(any(), any(), org.mockito.ArgumentMatchers.anyInt()))
                .thenReturn(List.of(record));
        when(taskDispatchRepository.findFirstByTaskIdOrderByCreatedAtDesc(TASK))
                .thenReturn(Optional.empty());

        scheduler.sweepStuckTasks();

        verify(taskRedispatchService).redispatch(record);
    }

    @Test
    void sweepSkipsTaskWithLiveDispatch() {
        TaskRecord record = stuckRecord("RETRY_WAIT");
        TaskDispatch live = dispatch();
        live.setStatus("PENDING");
        when(taskRecordService.listStuckTasks(any(), any(), org.mockito.ArgumentMatchers.anyInt()))
                .thenReturn(List.of(record));
        when(taskDispatchRepository.findFirstByTaskIdOrderByCreatedAtDesc(TASK))
                .thenReturn(Optional.of(live));

        scheduler.sweepStuckTasks();

        verify(taskRedispatchService, never()).redispatch(any());
    }

    @Test
    void sweepSkipsTaskWithRecentDispatch() {
        TaskRecord record = stuckRecord("QUEUED");
        TaskDispatch recent = dispatch();
        recent.setCreatedAt(Instant.now());
        when(taskRecordService.listStuckTasks(any(), any(), org.mockito.ArgumentMatchers.anyInt()))
                .thenReturn(List.of(record));
        when(taskDispatchRepository.findFirstByTaskIdOrderByCreatedAtDesc(TASK))
                .thenReturn(Optional.of(recent));

        scheduler.sweepStuckTasks();

        verify(taskRedispatchService, never()).redispatch(any());
    }
}
