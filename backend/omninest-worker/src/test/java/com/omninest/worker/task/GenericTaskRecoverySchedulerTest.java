package com.omninest.worker.task;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.concurrency.DistributedLock;
import com.omninest.modules.task.domain.TaskRecord;
import com.omninest.modules.task.service.StaleTaskRecovery;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import com.omninest.modules.task.service.TaskRedispatchService;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

/** 通用恢复调度器测试：心跳重投经 Outbox 退避、死信裁决与停滞任务清扫。 */
class GenericTaskRecoverySchedulerTest {

    private TaskRecordService taskRecordService;
    private TaskDispatchService taskDispatchService;
    private TaskRedispatchService taskRedispatchService;
    private DistributedLock distributedLock;
    private GenericTaskRecoveryScheduler scheduler;

    private static final UUID TASK = UUID.randomUUID();
    private static final UUID SECOND_TASK = UUID.randomUUID();
    private static final Instant CUTOFF = Instant.now().minusSeconds(600);
    private static final Instant NEXT_RETRY = Instant.now().plusSeconds(60);

    @BeforeEach
    void setUp() {
        taskRecordService = Mockito.mock(TaskRecordService.class);
        taskDispatchService = Mockito.mock(TaskDispatchService.class);
        taskRedispatchService = Mockito.mock(TaskRedispatchService.class);
        distributedLock = Mockito.mock(DistributedLock.class);
        // 单实例用例默认总能拿到清扫锁；并发语义由锁本身保证。
        Mockito.when(distributedLock.tryLock(Mockito.any(), Mockito.any(), Mockito.any())).thenReturn(true);
        scheduler = new GenericTaskRecoveryScheduler(
                taskRecordService, distributedLock,
                taskDispatchService, taskRedispatchService,
                new TransactionTemplate(Mockito.mock(PlatformTransactionManager.class)));
        ReflectionTestUtils.setField(scheduler, "staleHeartbeatSeconds", 600L);
        ReflectionTestUtils.setField(scheduler, "stuckDispatchSeconds", 1800L);
    }

    @Test
    void recoverSkipsWhenAnotherInstanceHoldsTheLock() {
        Mockito.when(distributedLock.tryLock(Mockito.any(), Mockito.any(), Mockito.any())).thenReturn(false);

        scheduler.recoverStaleTasks();

        // 并发恢复会重复重投同一任务，重投不改 retryCount，等于绕开重试上限。
        Mockito.verify(taskRecordService, Mockito.never())
                .listStaleRunningTaskIds(Mockito.any(), Mockito.any(), Mockito.anyInt());
    }

    @Test
    void transientRedispatchFailureKeepsTaskRecoverableInsteadOfDeadLetteringIt() {
        Mockito.when(taskRecordService.listStaleRunningTaskIds(Mockito.any(), Mockito.any(), Mockito.anyInt()))
                .thenReturn(List.of(TASK));
        Mockito.when(taskRecordService.recoverStaleTask(
                Mockito.eq(TASK), Mockito.any(), Mockito.any(), Mockito.any(), Mockito.anyString()))
                .thenReturn(new StaleTaskRecovery(true, false, null, null, 1, NEXT_RETRY));
        Mockito.when(taskDispatchService.latestRoute(TASK))
                .thenReturn(Optional.of(route("PUBLISHED", Instant.now().minusSeconds(7200))));
        Mockito.doThrow(new RuntimeException("broker down")).when(taskDispatchService).enqueueAt(
                Mockito.eq(TASK), Mockito.any(), Mockito.any(), Mockito.any(), Mockito.any());

        scheduler.recoverStaleTasks();

        // 重投失败必须整体回滚，任务留在 RUNNING 等下一轮；当场判死信会把
        // 一次数据库或 Broker 瞬断放大成永久失败。
        Mockito.verify(taskRecordService, Mockito.never())
                .markDeadLetter(Mockito.eq(TASK), Mockito.contains("REDISPATCH_FAILED"));
    }

    @Test
    void sweepSkipsWhenAnotherInstanceHoldsTheLock() {
        Mockito.when(distributedLock.tryLock(Mockito.any(), Mockito.any(), Mockito.any())).thenReturn(false);

        scheduler.sweepStuckTasks();

        // 两个实例同时清扫会重复重投同一任务，而重投不改 retryCount，等于绕开重试上限。
        Mockito.verify(taskRecordService, Mockito.never())
                .listStuckTasks(Mockito.any(), Mockito.any(), Mockito.anyInt());
    }

    private TaskDispatchService.TaskDispatchRoute route(String status, Instant createdAt) {
        return new TaskDispatchService.TaskDispatchRoute(
                "thumbnail.generate", "{\"fileNodeId\":\"1\"}", status, createdAt);
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
    @SuppressWarnings("unchecked")
    void heartbeatRecoveryCoversIndexRebuildAndNotificationEmail() {
        // 两者都会领取 RUNNING 且没有专用恢复调度器；遗漏会让崩溃后的任务永久卡在 RUNNING。
        List<String> taskTypes = (List<String>) ReflectionTestUtils.getField(
                GenericTaskRecoveryScheduler.class, "RECOVERED_TASK_TYPES");
        assertThat(taskTypes)
                .contains("SEARCH_INDEX_REBUILD", "NOTIFICATION_EMAIL")
                // MEDIA_SCAN 执行期间停留在 QUEUED，由停滞清扫兜底，不参与心跳恢复。
                .doesNotContain("MEDIA_SCAN");
    }

    @Test
    void republishesOriginalMessageThroughOutboxWithBackoff() {
        when(taskRecordService.listStaleRunningTaskIds(eq("THUMBNAIL"), any(), org.mockito.ArgumentMatchers.anyInt()))
                .thenReturn(List.of(TASK));
        when(taskRecordService.recoverStaleTask(
                eq(TASK), eq("THUMBNAIL"), any(), any(), anyString()))
                .thenReturn(new StaleTaskRecovery(true, false, null, null, 1, NEXT_RETRY));
        when(taskDispatchService.latestRoute(TASK))
                .thenReturn(Optional.of(route("PUBLISHED", Instant.now().minusSeconds(7200))));

        scheduler.recoverStaleTasks();

        // 重试状态与退避由 recoverStaleTask 单点完成，恢复重投不得重复计数。
        verify(taskRecordService, never()).markRetryWait(any(), anyString(), any());
        verify(taskDispatchService).enqueueAt(
                eq(TASK), eq("omni.task"), eq("thumbnail.generate"), any(), eq(NEXT_RETRY));
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
        when(taskDispatchService.latestRoute(TASK)).thenReturn(Optional.empty());

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
                "MEDIA_SCRAPE", "VIDEO_TRANSCODE", "WEB_OPTIMIZE",
                "AUDIO_EXTRACT", "THUMBNAIL", "TEXT_EXTRACTION",
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
        when(taskDispatchService.latestRoute(TASK)).thenReturn(Optional.empty());

        scheduler.sweepStuckTasks();

        verify(taskRedispatchService).redispatch(record);
    }

    @Test
    void sweepSkipsTaskWithLiveDispatch() {
        TaskRecord record = stuckRecord("RETRY_WAIT");
        Instant dispatchCreatedAt = Instant.now().minusSeconds(7200);
        when(taskRecordService.listStuckTasks(any(), any(), org.mockito.ArgumentMatchers.anyInt()))
                .thenReturn(List.of(record));
        when(taskDispatchService.latestRoutes(List.of(TASK)))
                .thenReturn(Map.of(TASK, route("PENDING", dispatchCreatedAt)));

        scheduler.sweepStuckTasks();

        verify(taskRedispatchService, never()).redispatch(any());
    }

    @Test
    void sweepSkipsTaskWithRecentDispatch() {
        TaskRecord record = stuckRecord("QUEUED");
        Instant dispatchCreatedAt = Instant.now();
        when(taskRecordService.listStuckTasks(any(), any(), org.mockito.ArgumentMatchers.anyInt()))
                .thenReturn(List.of(record));
        when(taskDispatchService.latestRoutes(List.of(TASK)))
                .thenReturn(Map.of(TASK, route("PUBLISHED", dispatchCreatedAt)));

        scheduler.sweepStuckTasks();

        verify(taskRedispatchService, never()).redispatch(any());
    }

    @Test
    void sweepReadsDispatchRoutesOncePerBatch() {
        TaskRecord first = stuckRecord("QUEUED");
        TaskRecord second = stuckRecord("RETRY_WAIT");
        second.setId(SECOND_TASK);
        when(taskRecordService.listStuckTasks(any(), any(), org.mockito.ArgumentMatchers.anyInt()))
                .thenReturn(List.of(first, second));
        when(taskDispatchService.latestRoutes(List.of(TASK, SECOND_TASK)))
                .thenReturn(Map.of());

        scheduler.sweepStuckTasks();

        // 逐个查询会让一轮清扫打出与任务数等量的单行 SELECT。
        verify(taskDispatchService).latestRoutes(List.of(TASK, SECOND_TASK));
        verify(taskDispatchService, never()).latestRoute(any());
        verify(taskRedispatchService).redispatch(first);
        verify(taskRedispatchService).redispatch(second);
    }
}
