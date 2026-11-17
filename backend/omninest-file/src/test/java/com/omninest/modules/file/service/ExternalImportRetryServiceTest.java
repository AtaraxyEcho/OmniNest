package com.omninest.modules.file.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.contains;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;
import java.time.Duration;
import java.util.Optional;
import java.util.UUID;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.file.domain.ImportTaskStatus;
import com.omninest.modules.file.domain.StorageImportTask;
import com.omninest.modules.file.event.ExternalImportRequestedEvent;
import com.omninest.modules.file.repository.FileIngressItemRepository;
import com.omninest.modules.file.repository.StorageImportTaskRepository;
import com.omninest.modules.notification.port.NotificationPublisher;
import com.omninest.modules.quota.service.StorageQuotaService;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.Mockito;

/**
 * 外部存储导入重试调度测试。
 *
 * @author OmniNest
 */
class ExternalImportRetryServiceTest {

    private static final UUID IMPORT_TASK_ID = UUID.fromString("70000000-0000-0000-0000-000000000001");
    private static final UUID SYSTEM_TASK_ID = UUID.fromString("70000000-0000-0000-0000-000000000002");
    private static final UUID OWNER_ID = UUID.fromString("70000000-0000-0000-0000-000000000003");

    private StorageImportTaskRepository importTaskRepository;
    private FileIngressItemRepository ingressItemRepository;
    private TaskRecordService taskRecordService;
    private TaskDispatchService taskDispatchService;
    private StorageQuotaService storageQuotaService;
    private NotificationPublisher notificationService;
    private ExternalImportRetryService service;

    @BeforeEach
    void setUp() {
        importTaskRepository = Mockito.mock(StorageImportTaskRepository.class);
        ingressItemRepository = Mockito.mock(FileIngressItemRepository.class);
        taskRecordService = Mockito.mock(TaskRecordService.class);
        taskDispatchService = Mockito.mock(TaskDispatchService.class);
        storageQuotaService = Mockito.mock(StorageQuotaService.class);
        notificationService = Mockito.mock(NotificationPublisher.class);
        service = new ExternalImportRetryService(
                importTaskRepository,
                taskRecordService,
                taskDispatchService,
                notificationService,
                new ExternalImportTaskStatusService(
                        importTaskRepository, ingressItemRepository, storageQuotaService));
        when(importTaskRepository.findById(IMPORT_TASK_ID)).thenReturn(Optional.of(task()));
    }

    @Test
    @DisplayName("瞬时失败按标准退避经 Outbox 延迟重投，不判业务终态")
    void transientFailureSchedulesDelayedRetry() {
        when(taskRecordService.retryCount(SYSTEM_TASK_ID)).thenReturn(0);
        when(taskRecordService.markRetryWait(eq(SYSTEM_TASK_ID), anyString(), any())).thenReturn(1);

        service.handleFailure(event(), ExternalImportTransientException.wrap(new java.io.IOException("rclone 抖动")));

        Mockito.verify(taskRecordService, Mockito.never())
                .markFailed(any(), anyString(), any());
        Mockito.verify(taskRecordService, Mockito.never()).markDeadLetter(any(), anyString(), any());
        ArgumentCaptor<Object> payload = ArgumentCaptor.forClass(Object.class);
        Mockito.verify(taskDispatchService).enqueueAt(
                eq(SYSTEM_TASK_ID),
                eq(QueueNames.TASK_EXCHANGE),
                eq(QueueNames.EXTERNAL_IMPORT_ROUTING_KEY),
                payload.capture(),
                any());
        assertThat(payload.getValue()).isInstanceOf(ExternalImportRequestedEvent.class);
        Mockito.verify(notificationService, Mockito.never())
                .notifyOrLog(any(), anyString(), anyString(), anyString(), any());
    }

    @Test
    @DisplayName("明确的业务错误直接终态并通知，不占用重试额度")
    void businessFailureTerminatesImmediately() {
        service.handleFailure(event(), new BusinessException(ErrorCode.FORBIDDEN, "账号无权限"));

        Mockito.verify(taskRecordService)
                .markFailed(eq(SYSTEM_TASK_ID), eq("FORBIDDEN"), any());
        Mockito.verify(taskDispatchService, Mockito.never())
                .enqueueAt(any(), any(), any(), any(), any());
        Mockito.verify(notificationService).notifyOrLog(
                eq(OWNER_ID), eq("TASK_FAILED"), anyString(), contains("FORBIDDEN"), any());
    }

    @Test
    @DisplayName("重试耗尽后转死信，并把业务行从执行中状态收口为失败")
    void exhaustedRetriesDeadLetterAndCloseBusinessRow() {
        when(taskRecordService.retryCount(SYSTEM_TASK_ID)).thenReturn(3);
        when(ingressItemRepository.sumImportedBytesByTaskId(IMPORT_TASK_ID)).thenReturn(1024L);

        service.handleFailure(event(), new IllegalStateException("依赖持续不可用"));

        Mockito.verify(taskRecordService)
                .markDeadLetter(eq(SYSTEM_TASK_ID), eq("IllegalStateException"), any());
        ArgumentCaptor<StorageImportTask> saved = ArgumentCaptor.forClass(StorageImportTask.class);
        Mockito.verify(importTaskRepository).save(saved.capture());
        assertThat(saved.getValue().getStatus()).isEqualTo(ImportTaskStatus.FAILED.getValue());
        // 死信路径没有执行线程再结算预留：必须在这里按已入库字节收口，否则配额锁死 24 小时。
        Mockito.verify(storageQuotaService)
                .settleReservation("EXTERNAL_IMPORT", IMPORT_TASK_ID, 1024L);
        Mockito.verify(notificationService).notifyOrLog(
                eq(OWNER_ID), eq("TASK_FAILED"), anyString(), anyString(), any());
    }

    @Test
    @DisplayName("包装层之下的业务错误仍按终态分类")
    void classificationFollowsCauseChain() {
        assertThat(ExternalImportRetryService.isTransient(
                ExternalImportTransientException.wrap(
                        new BusinessException(ErrorCode.FILE_QUOTA_EXCEEDED, "配额不足")))).isFalse();
        assertThat(ExternalImportRetryService.isTransient(
                ExternalImportTransientException.wrap(new java.io.IOException("timeout")))).isTrue();
    }

    private ExternalImportRequestedEvent event() {
        return new ExternalImportRequestedEvent(IMPORT_TASK_ID);
    }

    private StorageImportTask task() {
        StorageImportTask task = new StorageImportTask();
        task.setId(IMPORT_TASK_ID);
        task.setTaskId(SYSTEM_TASK_ID);
        task.setOwnerUserId(OWNER_ID);
        task.setStatus(ImportTaskStatus.TRANSFERRING.getValue());
        return task;
    }
}
