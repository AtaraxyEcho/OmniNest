package com.omninest.modules.file.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.messaging.QueueNames;
import com.omninest.common.rclone.RcloneGateway;
import com.omninest.common.storage.LocalExternalStorageSettings;
import com.omninest.modules.file.domain.ExternalStorageStatus;
import com.omninest.modules.file.domain.StorageExternalAccount;
import com.omninest.modules.file.domain.StorageImportTask;
import com.omninest.modules.file.dto.CreateImportTaskRequest;
import com.omninest.modules.file.dto.ExternalFileListDto;
import com.omninest.modules.file.event.ExternalImportRequestedEvent;
import com.omninest.modules.file.repository.StorageExternalAccountRepository;
import com.omninest.modules.file.repository.StorageImportTaskRepository;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

/**
 * ExternalStorageService 单元测试。
 *
 * @author OmniNest
 */
class ExternalStorageServiceTest {

    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID ACCOUNT_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");

    private final RcloneGateway rcloneGateway = mock(RcloneGateway.class);
    private final LocalExternalStorageSettings localStorageSettings = mock(LocalExternalStorageSettings.class);
    private final StorageExternalAccountRepository accountRepository =
            mock(StorageExternalAccountRepository.class);
    private final StorageImportTaskRepository importTaskRepository =
            mock(StorageImportTaskRepository.class);
    private final TaskDispatchService taskDispatchService = mock(TaskDispatchService.class);
    private final TaskRecordService taskRecordService = mock(TaskRecordService.class);

    private final ExternalStorageService service = new ExternalStorageService(
            rcloneGateway, localStorageSettings, accountRepository,
            importTaskRepository, taskDispatchService, taskRecordService
    );

    @Test
    void browseExternalStorage_returnsFileList() {
        // 构造账户：S3 类型、ACTIVE 状态、有效凭证
        StorageExternalAccount account = buildAccount("S3", ExternalStorageStatus.ACTIVE.getValue());
        when(accountRepository.findByIdAndOwnerUserId(ACCOUNT_ID, OWNER_ID))
                .thenReturn(Optional.of(account));

        // 模拟 rclone remote 已存在
        String remoteName = "omni-" + ACCOUNT_ID.toString().replace("-", "").substring(0, 8);
        when(rcloneGateway.listRemoteNames()).thenReturn(List.of(remoteName));

        // 构造 Rclone 目录条目返回
        RcloneGateway.DirectoryEntry file = new RcloneGateway.DirectoryEntry(
                "report.pdf",
                "report.pdf",
                false,
                2048L,
                null,
                "application/pdf",
                null,
                Map.of("Name", "report.pdf", "IsDir", false, "Size", 2048L)
        );
        when(rcloneGateway.listDirectory(eq(remoteName + ":"), eq("documents"), eq(false)))
                .thenReturn(List.of(file));

        // 执行浏览
        ExternalFileListDto result = service.browse(OWNER_ID, ACCOUNT_ID, "/documents");

        // 验证返回文件列表
        assertThat(result.items()).hasSize(1);
        assertThat(result.items().get(0).name()).isEqualTo("report.pdf");
        assertThat(result.items().get(0).isDir()).isFalse();
        assertThat(result.items().get(0).sizeBytes()).isEqualTo(2048L);
        assertThat(result.remotePath()).isEqualTo("/documents");

        verify(rcloneGateway).listDirectory(eq(remoteName + ":"), eq("documents"), eq(false));
    }

    @Test
    void browseExternalStorage_throwsWhenAccountNotFound() {
        // 模拟账户不存在
        when(accountRepository.findByIdAndOwnerUserId(ACCOUNT_ID, OWNER_ID))
                .thenReturn(Optional.empty());

        // 验证抛出 NOT_FOUND 异常
        assertThatThrownBy(() -> service.browse(OWNER_ID, ACCOUNT_ID, "/documents"))
                .isInstanceOf(BusinessException.class)
                .satisfies(ex -> {
                    BusinessException bex = (BusinessException) ex;
                    assertThat(bex.errorCode()).isEqualTo(ErrorCode.NOT_FOUND);
                })
                .hasMessageContaining("外部存储账户不存在");
    }

    @Test
    void cancelImportTask_marksSystemTaskCancelled() {
        UUID importTaskId = UUID.fromString("30000000-0000-0000-0000-000000000001");
        UUID systemTaskId = UUID.fromString("40000000-0000-0000-0000-000000000001");
        StorageImportTask task = new StorageImportTask();
        task.setId(importTaskId);
        task.setTaskId(systemTaskId);
        task.setOwnerUserId(OWNER_ID);
        task.setStatus("RUNNING");
        when(importTaskRepository.findByIdAndOwnerUserId(importTaskId, OWNER_ID))
                .thenReturn(Optional.of(task));
        when(importTaskRepository.save(any())).thenAnswer(invocation -> invocation.getArgument(0));

        service.cancelImportTask(OWNER_ID, importTaskId);

        assertThat(task.getStatus()).isEqualTo("CANCELLED");
        verify(importTaskRepository).save(task);
        verify(taskRecordService).markCancelled(systemTaskId);
    }

    @Test
    void resolveLocalHostPathUsesLocalStorageSettings() {
        StorageExternalAccount account = buildAccount("LOCAL", ExternalStorageStatus.ACTIVE.getValue());
        account.setEncryptedCredentials("{\"path\":\"/mnt/local/movies\"}");
        when(localStorageSettings.localHostRoot()).thenReturn("D:/external-storage");

        String hostPath = service.resolveLocalHostPath(account);

        assertThat(hostPath).isEqualTo("D:/external-storage/movies");
    }

    /**
     * 构造测试用外部存储账户。
     */
    private StorageExternalAccount buildAccount(String provider, String status) {
        StorageExternalAccount account = new StorageExternalAccount();
        account.setId(ACCOUNT_ID);
        account.setOwnerUserId(OWNER_ID);
        account.setProvider(provider);
        account.setDisplayName("测试存储");
        account.setEncryptedCredentials("{\"accessKey\":\"test\",\"secretKey\":\"test\"}");
        account.setStatus(status);
        return account;
    }

    @Test
    void createImportTaskEnqueuesThroughOutboxWithSystemTaskId() {
        when(accountRepository.findByIdAndOwnerUserId(ACCOUNT_ID, OWNER_ID))
                .thenReturn(Optional.of(buildAccount("WEBDAV", ExternalStorageStatus.ACTIVE.getValue())));
        when(importTaskRepository.save(any(StorageImportTask.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        service.createImportTask(OWNER_ID, ACCOUNT_ID,
                new CreateImportTaskRequest("/photos/vacation", null, null, null));

        ArgumentCaptor<UUID> recordIdCaptor = ArgumentCaptor.forClass(UUID.class);
        @SuppressWarnings("unchecked")
        ArgumentCaptor<Map<String, Object>> payloadCaptor = ArgumentCaptor.forClass(Map.class);
        verify(taskRecordService).createQueuedTask(
                recordIdCaptor.capture(),
                eq(OWNER_ID),
                eq("EXTERNAL_IMPORT"),
                eq(QueueNames.EXTERNAL_IMPORT_ROUTING_KEY),
                payloadCaptor.capture()
        );
        @SuppressWarnings("unchecked")
        ArgumentCaptor<ExternalImportRequestedEvent> eventCaptor =
                ArgumentCaptor.forClass(ExternalImportRequestedEvent.class);
        verify(taskDispatchService).enqueue(
                eq(recordIdCaptor.getValue()),
                eq(QueueNames.TASK_EXCHANGE),
                eq(QueueNames.EXTERNAL_IMPORT_ROUTING_KEY),
                eventCaptor.capture()
        );
        assertThat(eventCaptor.getValue().taskId().toString())
                .isEqualTo(payloadCaptor.getValue().get("importTaskId"));
    }
}
