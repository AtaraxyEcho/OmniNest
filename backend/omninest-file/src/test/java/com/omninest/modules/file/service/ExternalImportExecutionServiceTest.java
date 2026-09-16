package com.omninest.modules.file.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.error.BusinessException;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.messaging.DomainEventPublisher;
import com.omninest.common.rclone.RcloneGateway;
import com.omninest.common.storage.LocalExternalStorageSettings;
import com.omninest.common.storage.ObjectStorageBuckets;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.common.storage.ObjectStorageKey;
import com.omninest.modules.file.config.FileTransferLimitsProperties;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.FileObject;
import com.omninest.modules.file.domain.ImportSourceKind;
import com.omninest.modules.file.domain.ImportTaskStatus;
import com.omninest.modules.file.domain.StorageExternalAccount;
import com.omninest.modules.file.domain.StorageImportTask;
import com.omninest.modules.file.event.ExternalImportRequestedEvent;
import com.omninest.modules.file.service.FileIngressSafetyService.InspectionResult;
import com.omninest.common.security.MalwareScanGateway.Status;
import com.omninest.modules.file.repository.FileNodeRepository;
import com.omninest.modules.file.repository.FileObjectRepository;
import com.omninest.modules.file.repository.StorageExternalAccountRepository;
import com.omninest.modules.file.repository.StorageImportTaskRepository;
import com.omninest.modules.notification.service.NotificationService;
import com.omninest.modules.quota.service.StorageQuotaService;
import com.omninest.modules.task.service.TaskRecordService;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.function.Consumer;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
import org.springframework.transaction.TransactionStatus;
import org.springframework.transaction.support.TransactionCallback;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * ExternalImportExecutionService 单元测试。
 *
 * @author OmniNest
 */
class ExternalImportExecutionServiceTest {

    private static final UUID TASK_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID ACCOUNT_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");
    private static final UUID OWNER_ID = UUID.fromString("30000000-0000-0000-0000-000000000001");

    private final StorageImportTaskRepository importTaskRepository =
            mock(StorageImportTaskRepository.class);
    private final StorageExternalAccountRepository accountRepository =
            mock(StorageExternalAccountRepository.class);
    private final FileNodeRepository fileNodeRepository = mock(FileNodeRepository.class);
    private final FileObjectRepository fileObjectRepository = mock(FileObjectRepository.class);
    private final StorageQuotaService storageQuotaService = mock(StorageQuotaService.class);
    private final ObjectStorageClient objectStorageClient = mock(ObjectStorageClient.class);
    private final DomainEventPublisher domainEventPublisher = mock(DomainEventPublisher.class);
    private final FilePostProcessingTaskService postProcessingTaskService =
            mock(FilePostProcessingTaskService.class);
    private final RcloneGateway rcloneGateway = mock(RcloneGateway.class);
    private final LocalExternalStorageSettings localStorageSettings = mock(LocalExternalStorageSettings.class);
    private final ExternalStorageService externalStorageService = mock(ExternalStorageService.class);
    private final ObjectStorageBuckets objectStorageBuckets = mock(ObjectStorageBuckets.class);
    private final TransactionTemplate transactionTemplate = mock(TransactionTemplate.class);
    private final NotificationService notificationService = mock(NotificationService.class);
    private final TaskRecordService taskRecordService = mock(TaskRecordService.class);
    private final BoundedFileTreeScanner fileTreeScanner = fileTreeScanner();
    private final FileIngressSafetyService ingressSafetyService = mock(FileIngressSafetyService.class);
    private final FileIngressLifecycleService ingressLifecycleService = mock(FileIngressLifecycleService.class);

    private final ExternalImportExecutionService service = new ExternalImportExecutionService(
            importTaskRepository, accountRepository, fileNodeRepository, fileObjectRepository,
            storageQuotaService, mock(SharedSpaceQuotaService.class), objectStorageClient, domainEventPublisher, postProcessingTaskService,
            rcloneGateway, localStorageSettings, externalStorageService,
            objectStorageBuckets, transactionTemplate, notificationService, taskRecordService,
            fileTreeScanner, ingressSafetyService, ingressLifecycleService
    );

    private static BoundedFileTreeScanner fileTreeScanner() {
        return new BoundedFileTreeScanner(new FileTransferLimitsProperties());
    }

    @BeforeEach
    void setUpTaskClaim() {
        when(taskRecordService.claimForExecution(any(UUID.class), any(String.class))).thenReturn(true);
        when(objectStorageBuckets.quarantine()).thenReturn("file-quarantine");
        when(ingressLifecycleService.open(any())).thenReturn(UUID.randomUUID());
        when(ingressSafetyService.inspect(any(ObjectStorageKey.class), anyLong(), anyString(), any(UUID.class)))
                .thenReturn(new InspectionResult(Status.CLEAN, "文件安全", "0".repeat(64)));
    }

    @Test
    void execute_throwsWhenAccountNotFound() throws Exception {
        // 模拟 TransactionTemplate 直接执行回调（markRunning 使用）
        when(transactionTemplate.execute(any())).thenAnswer(invocation -> {
            TransactionCallback<?> callback = invocation.getArgument(0);
            return callback.doInTransaction(null);
        });

        // 构造 QUEUED 状态的导入任务
        StorageImportTask task = new StorageImportTask();
        task.setId(TASK_ID);
        task.setOwnerUserId(OWNER_ID);
        task.setExternalAccountId(ACCOUNT_ID);
        task.setSourcePath("/mnt/local/test.mp4");
        task.setFileName("test.mp4");
        task.setStatus(ImportTaskStatus.QUEUED.getValue());
        when(importTaskRepository.findById(TASK_ID)).thenReturn(Optional.of(task));
        when(importTaskRepository.save(any())).thenAnswer(inv -> inv.getArgument(0));

        Method updateProgress = ExternalImportExecutionService.class
                .getDeclaredMethod("updateTransferredBytes", UUID.class, long.class);
        updateProgress.setAccessible(true);
        updateProgress.invoke(service, TASK_ID, 1L);
        Field throttleField = ExternalImportExecutionService.class.getDeclaredField("progressThrottle");
        throttleField.setAccessible(true);
        @SuppressWarnings("unchecked")
        Map<UUID, Object> throttle = (Map<UUID, Object>) throttleField.get(service);
        assertThat(throttle).containsKey(TASK_ID);

        // 模拟外部存储账户不存在
        when(accountRepository.findById(ACCOUNT_ID)).thenReturn(Optional.empty());

        // 执行并验证异常
        ExternalImportRequestedEvent event = new ExternalImportRequestedEvent(TASK_ID);
        assertThatThrownBy(() -> service.execute(event))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("外部存储账户不存在");

        // 验证账户查询被正确调用
        verify(accountRepository).findById(ACCOUNT_ID);
        assertThat(throttle).doesNotContainKey(TASK_ID);
    }

    @Test
    void execute_rejectsLocalProvider() throws Exception {
        when(transactionTemplate.execute(any())).thenAnswer(invocation -> {
            TransactionCallback<?> callback = invocation.getArgument(0);
            return callback.doInTransaction(null);
        });
        Mockito.doAnswer(invocation -> {
            @SuppressWarnings("unchecked")
            Consumer<TransactionStatus> callback =
                    (Consumer<TransactionStatus>) invocation.getArgument(0);
            callback.accept(null);
            return null;
        }).when(transactionTemplate).executeWithoutResult(any());

        StorageImportTask task = new StorageImportTask();
        task.setId(TASK_ID);
        task.setOwnerUserId(OWNER_ID);
        task.setExternalAccountId(ACCOUNT_ID);
        task.setSourcePath("movies/a.mkv");
        task.setFileName("a.mkv");
        task.setStatus(ImportTaskStatus.QUEUED.getValue());
        when(importTaskRepository.findById(TASK_ID)).thenReturn(Optional.of(task));
        when(importTaskRepository.save(any())).thenAnswer(inv -> inv.getArgument(0));

        StorageExternalAccount account = new StorageExternalAccount();
        account.setId(ACCOUNT_ID);
        account.setOwnerUserId(OWNER_ID);
        account.setProvider("LOCAL");
        account.setEncryptedCredentials("{\"path\":\"/mnt/local\"}");
        account.setStatus("ACTIVE");
        when(accountRepository.findById(ACCOUNT_ID)).thenReturn(Optional.of(account));

        service.execute(new ExternalImportRequestedEvent(TASK_ID));

        verify(objectStorageClient, Mockito.never()).putObject(any(), any(), any(long.class), any());
        assertThat(task.getStatus()).isEqualTo(ImportTaskStatus.FAILED.getValue());
    }

    @Test
    void execute_usesFileCopyForRcloneFileSource() throws Exception {
        when(transactionTemplate.execute(any())).thenAnswer(invocation -> {
            TransactionCallback<?> callback = invocation.getArgument(0);
            return callback.doInTransaction(null);
        });
        Mockito.doAnswer(invocation -> {
            @SuppressWarnings("unchecked")
            Consumer<TransactionStatus> callback =
                    (Consumer<TransactionStatus>) invocation.getArgument(0);
            callback.accept(null);
            return null;
        }).when(transactionTemplate).executeWithoutResult(any());

        Path importRoot = Files.createTempDirectory("omni-rclone-import-test");
        try {
            StorageImportTask task = new StorageImportTask();
            task.setId(TASK_ID);
            task.setOwnerUserId(OWNER_ID);
            task.setExternalAccountId(ACCOUNT_ID);
            task.setSourcePath("series/episode-01.mkv");
            task.setSourceKind(ImportSourceKind.FILE.getValue());
            task.setFileName("episode-01.mkv");
            task.setStatus(ImportTaskStatus.QUEUED.getValue());
            when(importTaskRepository.findById(TASK_ID)).thenReturn(Optional.of(task));
            when(importTaskRepository.save(any())).thenAnswer(invocation -> invocation.getArgument(0));

            StorageExternalAccount account = new StorageExternalAccount();
            account.setId(ACCOUNT_ID);
            account.setOwnerUserId(OWNER_ID);
            account.setProvider("S3");
            account.setStatus("ACTIVE");
            when(accountRepository.findById(ACCOUNT_ID)).thenReturn(Optional.of(account));
            when(externalStorageService.resolveFs(account)).thenReturn("remote:");
            when(localStorageSettings.importHostRoot()).thenReturn(importRoot.toString());
            when(localStorageSettings.importContainerRoot()).thenReturn("/mnt/imports");
            when(rcloneGateway.startFileCopy(
                    eq("remote:"),
                    eq("series/episode-01.mkv"),
                    eq("local:/mnt/imports/" + TASK_ID),
                    eq("episode-01.mkv"),
                    eq("import-" + TASK_ID)
            )).thenReturn(42);
            when(rcloneGateway.queryJobStatus(42)).thenReturn(
                    new RcloneGateway.JobStatus(true, true, null)
            );

            service.execute(new ExternalImportRequestedEvent(TASK_ID));

            verify(rcloneGateway).startFileCopy(
                    "remote:",
                    "series/episode-01.mkv",
                    "local:/mnt/imports/" + TASK_ID,
                    "episode-01.mkv",
                    "import-" + TASK_ID
            );
        } finally {
            Files.deleteIfExists(importRoot);
        }
    }

}

