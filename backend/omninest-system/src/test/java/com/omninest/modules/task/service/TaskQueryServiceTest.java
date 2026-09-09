package com.omninest.modules.task.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.enums.ErrorCode;
import com.omninest.modules.task.domain.TaskStatus;
import com.omninest.common.error.BusinessException;
import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.task.domain.TaskRecord;
import com.omninest.modules.task.dto.TaskDto;
import com.omninest.modules.task.repository.TaskDispatchRepository;
import com.omninest.modules.task.repository.TaskRecordRepository;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;

import static org.mockito.Mockito.never;

/**
 * TaskQueryService 单元测试
 */
@ExtendWith(MockitoExtension.class)
class TaskQueryServiceTest {
    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");

    @Mock
    private TaskRecordRepository taskRecordRepository;

    @Mock
    private TaskDispatchService taskDispatchService;

    @Mock
    private TaskDispatchRepository taskDispatchRepository;

    private TaskQueryService taskQueryService;

    @BeforeEach
    void setUp() {
        taskQueryService = new TaskQueryService(
                taskRecordRepository,
                new TaskRedispatchService(taskDispatchService, taskDispatchRepository)
        );
    }

    /**
     * 创建测试用任务记录
     */
    private TaskRecord createTaskRecord(String status) {
        TaskRecord record = new TaskRecord();
        record.setId(UUID.randomUUID());
        record.setOwnerUserId(OWNER_ID);
        record.setTaskType("FILE_INDEX");
        record.setStatus(status);
        record.setRetryCount(0);
        record.setProgress(0);
        record.setMaxRetries(3);
        record.setCreatedAt(Instant.now());
        record.setUpdatedAt(Instant.now());
        record.setVersion(0);
        return record;
    }

    @Nested
    @DisplayName("list 方法测试")
    class ListTests {

        @Test
        @DisplayName("无状态过滤时返回全部任务")
        void list_noStatusFilter_returnsAllTasks() {
            // Arrange
            Pageable pageable = PageRequest.of(0, 20);
            TaskRecord task1 = createTaskRecord("QUEUED");
            TaskRecord task2 = createTaskRecord("COMPLETED");
            Page<TaskRecord> page = new PageImpl<>(List.of(task1, task2), pageable, 2);
            when(taskRecordRepository.findByOwnerUserId(OWNER_ID, pageable)).thenReturn(page);

            // Act
            Page<TaskDto> result = taskQueryService.listOwned(OWNER_ID, null, pageable);

            // Assert
            assertThat(result.getContent()).hasSize(2);
            assertThat(result.getTotalElements()).isEqualTo(2);
            verify(taskRecordRepository).findByOwnerUserId(OWNER_ID, pageable);
        }

        @Test
        @DisplayName("空字符串状态过滤时返回全部任务")
        void list_emptyStatusFilter_returnsAllTasks() {
            // Arrange
            Pageable pageable = PageRequest.of(0, 20);
            Page<TaskRecord> page = new PageImpl<>(List.of(), pageable, 0);
            when(taskRecordRepository.findByOwnerUserId(OWNER_ID, pageable)).thenReturn(page);

            // Act
            Page<TaskDto> result = taskQueryService.listOwned(OWNER_ID, "", pageable);

            // Assert
            assertThat(result.getContent()).isEmpty();
            verify(taskRecordRepository).findByOwnerUserId(OWNER_ID, pageable);
        }

        @Test
        @DisplayName("指定状态过滤时返回匹配任务")
        void list_withStatusFilter_returnsMatchingTasks() {
            // Arrange
            Pageable pageable = PageRequest.of(0, 20);
            TaskRecord task = createTaskRecord("QUEUED");
            Page<TaskRecord> page = new PageImpl<>(List.of(task), pageable, 1);
            when(taskRecordRepository.findByOwnerUserIdAndStatus(OWNER_ID, "QUEUED", pageable)).thenReturn(page);

            // Act
            Page<TaskDto> result = taskQueryService.listOwned(OWNER_ID, "QUEUED", pageable);

            // Assert
            assertThat(result.getContent()).hasSize(1);
            assertThat(result.getContent().get(0).status()).isEqualTo("QUEUED");
            verify(taskRecordRepository).findByOwnerUserIdAndStatus(OWNER_ID, "QUEUED", pageable);
        }

        @Test
        @DisplayName("指定状态无匹配时返回空结果")
        void list_withStatusFilter_noMatch_returnsEmpty() {
            // Arrange
            Pageable pageable = PageRequest.of(0, 20);
            Page<TaskRecord> page = new PageImpl<>(List.of(), pageable, 0);
            when(taskRecordRepository.findByOwnerUserIdAndStatus(OWNER_ID, "FAILED", pageable)).thenReturn(page);

            // Act
            Page<TaskDto> result = taskQueryService.listOwned(OWNER_ID, "FAILED", pageable);

            // Assert
            assertThat(result.getContent()).isEmpty();
            verify(taskRecordRepository).findByOwnerUserIdAndStatus(OWNER_ID, "FAILED", pageable);
        }
    }

    @Nested
    @DisplayName("listDlq 方法测试")
    class ListDlqTests {

        @Test
        @DisplayName("返回死信队列中的任务")
        void listDlq_returnsDeadLetterTasks() {
            // Arrange
            TaskRecord dlqTask = createTaskRecord(TaskStatus.DLQ.getValue());
            when(taskRecordRepository.findByStatusOrderByCreatedAtDesc(
                    eq(TaskStatus.DLQ.getValue()), any(PageRequest.class)))
                    .thenReturn(List.of(dlqTask));

            // Act
            List<TaskDto> result = taskQueryService.listDlq(20);

            // Assert
            assertThat(result).hasSize(1);
            assertThat(result.get(0).status()).isEqualTo(TaskStatus.DLQ.getValue());
        }

        @Test
        @DisplayName("死信队列为空时返回空列表")
        void listDlq_emptyQueue_returnsEmptyList() {
            // Arrange
            when(taskRecordRepository.findByStatusOrderByCreatedAtDesc(
                    eq(TaskStatus.DLQ.getValue()), any(PageRequest.class)))
                    .thenReturn(List.of());

            // Act
            List<TaskDto> result = taskQueryService.listDlq(20);

            // Assert
            assertThat(result).isEmpty();
        }
    }

    @Nested
    @DisplayName("retryDlqEntry 方法测试")
    class RetryDlqEntryTests {

        @Test
        @DisplayName("重试死信任务成功并经 Outbox 重新投递")
        void retryDlqEntry_validDeadLetterTask_retriesSuccessfully() {
            // Arrange
            UUID taskId = UUID.randomUUID();
            TaskRecord dlqTask = createTaskRecord(TaskStatus.DLQ.getValue());
            dlqTask.setId(taskId);
            dlqTask.setRetryCount(3);
            dlqTask.setErrorMessage("处理失败");
            dlqTask.setRoutingKey(QueueNames.OFFLINE_DOWNLOAD_ROUTING_KEY);
            dlqTask.setPayload("{\"taskId\":\"" + taskId + "\"}");
            when(taskRecordRepository.findById(taskId)).thenReturn(Optional.of(dlqTask));

            // Act
            taskQueryService.retryDlqEntry(taskId);

            // Assert
            assertThat(dlqTask.getStatus()).isEqualTo("QUEUED");
            assertThat(dlqTask.getRetryCount()).isZero();
            assertThat(dlqTask.getErrorMessage()).isNull();
            verify(taskRecordRepository).save(dlqTask);
            @SuppressWarnings("unchecked")
            ArgumentCaptor<Map<String, Object>> payloadCaptor = ArgumentCaptor.forClass(Map.class);
            verify(taskDispatchService).enqueue(
                    eq(taskId),
                    eq(QueueNames.TASK_EXCHANGE),
                    eq(QueueNames.OFFLINE_DOWNLOAD_ROUTING_KEY),
                    payloadCaptor.capture()
            );
            assertThat(payloadCaptor.getValue()).containsEntry("taskId", taskId.toString());
        }

        @Test
        @DisplayName("载荷无法重建时重试失败")
        void retryDlqEntry_missingRoutingKey_throwsException() {
            // Arrange
            UUID taskId = UUID.randomUUID();
            TaskRecord dlqTask = createTaskRecord(TaskStatus.DLQ.getValue());
            dlqTask.setId(taskId);
            when(taskRecordRepository.findById(taskId)).thenReturn(Optional.of(dlqTask));

            // Act & Assert
            assertThatThrownBy(() -> taskQueryService.retryDlqEntry(taskId))
                    .isInstanceOf(BusinessException.class);
            verify(taskDispatchService, never()).enqueue(any(), any(), any(), any());
        }

        @Test
        @DisplayName("任务不存在时抛出异常")
        void retryDlqEntry_taskNotFound_throwsException() {
            // Arrange
            UUID taskId = UUID.randomUUID();
            when(taskRecordRepository.findById(taskId)).thenReturn(Optional.empty());

            // Act & Assert
            assertThatThrownBy(() -> taskQueryService.retryDlqEntry(taskId))
                    .isInstanceOf(BusinessException.class)
                    .satisfies(ex -> {
                        BusinessException bex = (BusinessException) ex;
                        assertThat(bex.errorCode()).isEqualTo(ErrorCode.TASK_NOT_FOUND);
                    });
        }

        @Test
        @DisplayName("非死信任务不可重试")
        void retryDlqEntry_nonDeadLetterTask_throwsException() {
            // Arrange
            UUID taskId = UUID.randomUUID();
            TaskRecord queuedTask = createTaskRecord("QUEUED");
            queuedTask.setId(taskId);
            when(taskRecordRepository.findById(taskId)).thenReturn(Optional.of(queuedTask));

            // Act & Assert
            assertThatThrownBy(() -> taskQueryService.retryDlqEntry(taskId))
                    .isInstanceOf(BusinessException.class)
                    .satisfies(ex -> {
                        BusinessException bex = (BusinessException) ex;
                        assertThat(bex.errorCode()).isEqualTo(ErrorCode.TASK_STATUS_ILLEGAL);
                    });
        }
    }
}
