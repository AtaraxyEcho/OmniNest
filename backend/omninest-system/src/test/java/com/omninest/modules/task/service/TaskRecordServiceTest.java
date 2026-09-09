package com.omninest.modules.task.service;

import com.omninest.modules.task.domain.TaskStatus;
import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncEventCommand;
import com.omninest.common.sync.SyncScope;
import com.omninest.common.sync.UserSyncEventRecorder;
import com.omninest.modules.task.domain.TaskRecord;
import com.omninest.modules.task.repository.TaskRecordRepository;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import org.assertj.core.api.Assertions;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.Mockito;

/**
 * 通用任务状态同步事件测试。
 *
 * @author OmniNest
 */
class TaskRecordServiceTest {

    private final TaskRecordRepository taskRecordRepository = Mockito.mock(TaskRecordRepository.class);
    private final UserSyncEventRecorder syncEventRecorder = Mockito.mock(UserSyncEventRecorder.class);
    private final TaskRecordService service = new TaskRecordService(taskRecordRepository, syncEventRecorder);

    @Test
    void createQueuedTask_recordsCreatedEvent() {
        UUID taskId = UUID.randomUUID();
        UUID ownerUserId = UUID.randomUUID();
        Mockito.when(taskRecordRepository.save(Mockito.any(TaskRecord.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        service.createQueuedTask(taskId, ownerUserId, "PHOTO_SCAN", "photo.scan", Map.of());

        ArgumentCaptor<SyncEventCommand> captor = ArgumentCaptor.forClass(SyncEventCommand.class);
        Mockito.verify(syncEventRecorder).record(captor.capture());
        Assertions.assertThat(captor.getValue().recipientUserId()).isEqualTo(ownerUserId);
        Assertions.assertThat(captor.getValue().scope()).isEqualTo(SyncScope.TASKS);
        Assertions.assertThat(captor.getValue().resourceType()).isEqualTo("TASK_PHOTO_SCAN");
        Assertions.assertThat(captor.getValue().action()).isEqualTo(SyncAction.CREATED);
        Assertions.assertThat(captor.getValue().resourceId()).isEqualTo(taskId.toString());
    }

    @Test
    void updateProgress_recordsEventWhenCrossingFivePercentBoundary() {
        TaskRecord record = taskRecord(4);
        Mockito.when(taskRecordRepository.findById(record.getId())).thenReturn(Optional.of(record));

        service.updateProgress(record.getId(), 5);

        ArgumentCaptor<SyncEventCommand> captor = ArgumentCaptor.forClass(SyncEventCommand.class);
        Mockito.verify(syncEventRecorder).record(captor.capture());
        Assertions.assertThat(captor.getValue().action()).isEqualTo(SyncAction.PROGRESS);
        Assertions.assertThat(captor.getValue().hints()).containsEntry("progress", 5);
    }

    @Test
    void updateProgress_skipsEventInsideSameFivePercentBoundary() {
        TaskRecord record = taskRecord(1);
        Mockito.when(taskRecordRepository.findById(record.getId())).thenReturn(Optional.of(record));

        service.updateProgress(record.getId(), 4);

        Mockito.verifyNoInteractions(syncEventRecorder);
    }

    @Test
    void updateProgress_refreshesHeartbeatToPreventFalseRecovery() {
        TaskRecord record = taskRecord(1);
        Mockito.when(taskRecordRepository.findById(record.getId())).thenReturn(Optional.of(record));

        service.updateProgress(record.getId(), 2);

        // 进度推进必须同步刷新心跳，否则长任务会被心跳恢复调度误判死亡并重投双跑。
        Assertions.assertThat(record.getHeartbeatAt()).isNotNull();
    }

    @Test
    void deleteTerminalTaskBatchUpdatedBeforeDeletesBoundedIds() {
        Instant cutoff = Instant.parse("2026-06-01T00:00:00Z");
        List<String> statuses = List.of(
                TaskStatus.COMPLETED.getValue(),
                TaskStatus.FAILED.getValue(),
                TaskStatus.CANCELLED.getValue()
        );
        List<UUID> taskIds = List.of(UUID.randomUUID(), UUID.randomUUID());
        Mockito.when(taskRecordRepository.findIdsByStatusInAndUpdatedAtBefore(
                Mockito.eq(statuses),
                Mockito.eq(cutoff),
                Mockito.any()
        )).thenReturn(taskIds);

        int result = service.deleteTerminalTaskBatchUpdatedBefore(cutoff, 2);

        Assertions.assertThat(result).isEqualTo(2);
        Mockito.verify(taskRecordRepository).deleteAllByIdInBatch(taskIds);
    }

    @Test
    void markDeadLetterUpdatesExistingTaskAndRecordsFailureEvent() {
        TaskRecord record = taskRecord(75);
        Mockito.when(taskRecordRepository.findById(record.getId())).thenReturn(Optional.of(record));

        boolean updated = service.markDeadLetter(record.getId(), "消息进入死信队列");

        Assertions.assertThat(updated).isTrue();
        Assertions.assertThat(record.getStatus()).isEqualTo(TaskStatus.DLQ.getValue());
        Assertions.assertThat(record.getErrorMessage()).isEqualTo("消息进入死信队列");
        Assertions.assertThat(record.getCompletedAt()).isNotNull();
        Mockito.verify(taskRecordRepository).save(record);
        ArgumentCaptor<SyncEventCommand> captor = ArgumentCaptor.forClass(SyncEventCommand.class);
        Mockito.verify(syncEventRecorder).record(captor.capture());
        Assertions.assertThat(captor.getValue().action()).isEqualTo(SyncAction.FAILED);
    }

    @Test
    void markDeadLetterReturnsFalseWhenTaskDoesNotExist() {
        UUID taskId = UUID.randomUUID();
        Mockito.when(taskRecordRepository.findById(taskId)).thenReturn(Optional.empty());

        boolean updated = service.markDeadLetter(taskId, "消息进入死信队列");

        Assertions.assertThat(updated).isFalse();
        Mockito.verifyNoInteractions(syncEventRecorder);
    }

    @Test
    void cancelledTaskCannotBeCompletedByLateWorkerMessage() {
        TaskRecord record = taskRecord(60);
        record.setStatus(TaskStatus.CANCELLED.getValue());
        Mockito.when(taskRecordRepository.findById(record.getId())).thenReturn(Optional.of(record));

        service.markCompleted(record.getId(), Map.of("status", "late"));

        Assertions.assertThat(record.getStatus()).isEqualTo(TaskStatus.CANCELLED.getValue());
        Mockito.verify(taskRecordRepository, Mockito.never()).save(record);
        Mockito.verifyNoInteractions(syncEventRecorder);
    }

    @Test
    void cancelActiveResourceTasksUsesSingleBulkUpdate() {
        UUID ownerUserId = UUID.randomUUID();
        List<UUID> resourceIds = List.of(UUID.randomUUID(), UUID.randomUUID());
        List<String> activeStatuses = List.of(
                TaskStatus.QUEUED.getValue(),
                TaskStatus.RUNNING.getValue()
        );
        Mockito.when(taskRecordRepository.cancelActiveResourceTasks(
                Mockito.eq(ownerUserId),
                Mockito.eq("FILE_NODE"),
                Mockito.eq(resourceIds),
                Mockito.eq(activeStatuses),
                Mockito.eq("FILE_PURGE"),
                Mockito.eq(TaskStatus.CANCELLED.getValue()),
                Mockito.any(Instant.class)
        )).thenReturn(2);

        int cancelled = service.cancelActiveResourceTasks(
                ownerUserId,
                "FILE_NODE",
                resourceIds,
                activeStatuses,
                "FILE_PURGE"
        );

        Assertions.assertThat(cancelled).isEqualTo(2);
    }

    private TaskRecord taskRecord(int progress) {
        TaskRecord record = new TaskRecord();
        record.setId(UUID.randomUUID());
        record.setOwnerUserId(UUID.randomUUID());
        record.setTaskType("PHOTO_SCAN");
        record.setStatus("RUNNING");
        record.setProgress(progress);
        return record;
    }
}
