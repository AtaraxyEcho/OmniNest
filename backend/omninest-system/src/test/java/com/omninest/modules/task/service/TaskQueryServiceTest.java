package com.omninest.modules.task.service;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.error.BusinessException;
import com.omninest.modules.task.domain.TaskRecord;
import com.omninest.modules.task.domain.TaskStatus;
import com.omninest.modules.task.repository.TaskRecordRepository;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;

class TaskQueryServiceTest {

    private static final UUID OWNER = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID OTHER = UUID.fromString("10000000-0000-0000-0000-000000000002");
    private static final UUID TASK_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");

    private final TaskRecordRepository repository = mock(TaskRecordRepository.class);
    private final TaskRedispatchService redispatchService = mock(TaskRedispatchService.class);
    private final TaskQueryService service = new TaskQueryService(repository, redispatchService);

    @Test
    void retryOwnedRejectsForeignOwner() {
        TaskRecord task = task(TaskStatus.FAILED, OWNER);
        when(repository.findById(TASK_ID)).thenReturn(Optional.of(task));

        assertThatThrownBy(() -> service.retryOwned(OTHER, TASK_ID))
                .isInstanceOf(BusinessException.class);
    }

    @Test
    void retryOwnedRejectsDlq() {
        TaskRecord task = task(TaskStatus.DLQ, OWNER);
        when(repository.findById(TASK_ID)).thenReturn(Optional.of(task));

        assertThatThrownBy(() -> service.retryOwned(OWNER, TASK_ID))
                .isInstanceOf(BusinessException.class);
    }

    @Test
    void retryOwnedQueuesAndRedispatchesFailedTask() {
        TaskRecord task = task(TaskStatus.FAILED, OWNER);
        when(repository.findById(TASK_ID)).thenReturn(Optional.of(task));

        service.retryOwned(OWNER, TASK_ID);

        verify(repository).save(task);
        verify(redispatchService).redispatch(task);
    }

    private TaskRecord task(TaskStatus status, UUID owner) {
        TaskRecord record = new TaskRecord();
        record.setId(TASK_ID);
        record.setOwnerUserId(owner);
        record.setTaskType("FILE_INDEX");
        record.setStatus(status.getValue());
        record.setRetryCount(2);
        return record;
    }
}
