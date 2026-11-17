package com.omninest.modules.task.dto;

import static org.assertj.core.api.Assertions.assertThat;

import com.omninest.modules.task.domain.TaskRecord;
import java.time.Instant;
import java.util.UUID;
import org.junit.jupiter.api.Test;

class TaskDtoTest {

    @Test
    void fromOmitsStackSummaryForOwnerView() {
        TaskRecord record = failedRecord();
        record.setStackSummary("java.lang.RuntimeException: boom");
        record.setResult("{\"fileId\":\"abc\"}");

        TaskDto dto = TaskDto.from(record);

        assertThat(dto.stackSummary()).isNull();
        assertThat(dto.errorSummary()).isEqualTo("failed");
        assertThat(dto.result()).isEqualTo("{\"fileId\":\"abc\"}");
    }

    @Test
    void fromIncludesStackSummaryWhenDiagnosticsRequested() {
        TaskRecord record = failedRecord();
        record.setStackSummary("java.lang.RuntimeException: boom");

        TaskDto dto = TaskDto.from(record, true);

        assertThat(dto.stackSummary()).isEqualTo("java.lang.RuntimeException: boom");
    }

    private TaskRecord failedRecord() {
        TaskRecord record = new TaskRecord();
        record.setId(UUID.fromString("30000000-0000-0000-0000-000000000001"));
        record.setTaskType("FILE_INDEX");
        record.setStatus("FAILED");
        record.setProgress(10);
        record.setRetryCount(1);
        record.setErrorMessage("failed");
        record.setUpdatedAt(Instant.parse("2026-01-01T00:00:00Z"));
        return record;
    }
}
