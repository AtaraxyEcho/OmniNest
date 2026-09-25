package com.omninest.modules.file.service;

import static org.mockito.ArgumentMatchers.any;

import com.omninest.common.download.OfflineDownloadGateway;
import com.omninest.common.download.OfflineDownloadGateway.TaskSnapshot;
import com.omninest.common.download.OfflineDownloadSourceResolver;
import com.omninest.common.download.OfflineDownloadSourceResolver.ResolvedSource;
import com.omninest.common.download.OfflineDownloadSourceResolver.SourceKind;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.messaging.DomainEventPublisher;
import com.omninest.common.security.SafeUrlValidator;
import com.omninest.common.storage.ObjectStorageBuckets;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.common.storage.ObjectStorageKey;
import com.omninest.modules.file.config.FileTransferLimitsProperties;
import com.omninest.modules.file.domain.DownloadOfflineTask;
import com.omninest.modules.file.event.OfflineDownloadRequestedEvent;
import com.omninest.modules.file.service.FileIngressSafetyService.InspectionResult;
import com.omninest.common.security.MalwareScanGateway.Status;
import com.omninest.modules.file.repository.DownloadOfflineTaskRepository;
import com.omninest.modules.file.repository.FileNodeRepository;
import com.omninest.modules.file.repository.FileObjectRepository;
import com.omninest.modules.notification.service.NotificationService;
import com.omninest.modules.quota.service.StorageQuotaService;
import com.omninest.modules.task.domain.TaskStatus;
import com.omninest.modules.task.service.TaskRecordService;
import java.net.URI;
import java.nio.file.Path;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
import org.springframework.transaction.support.TransactionCallback;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * OfflineDownloadExecutionService 单元测试。
 *
 * @author OmniNest
 */
class OfflineDownloadExecutionServiceTest {

    private static final UUID TASK_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");

    private final DownloadOfflineTaskRepository offlineTaskRepository =
            Mockito.mock(DownloadOfflineTaskRepository.class);
    private final FileNodeRepository fileNodeRepository = Mockito.mock(FileNodeRepository.class);
    private final FileObjectRepository fileObjectRepository = Mockito.mock(FileObjectRepository.class);
    private final StorageQuotaService storageQuotaService = Mockito.mock(StorageQuotaService.class);
    private final ObjectStorageClient objectStorageClient = Mockito.mock(ObjectStorageClient.class);
    private final DomainEventPublisher domainEventPublisher = Mockito.mock(DomainEventPublisher.class);
    private final FilePostProcessingTaskService postProcessingTaskService =
            Mockito.mock(FilePostProcessingTaskService.class);
    private final OfflineDownloadSourceResolver sourceResolver =
            Mockito.mock(OfflineDownloadSourceResolver.class);
    private final OfflineDownloadGateway offlineDownloadGateway = Mockito.mock(OfflineDownloadGateway.class);
    private final ObjectStorageBuckets objectStorageBuckets = Mockito.mock(ObjectStorageBuckets.class);
    private final TransactionTemplate transactionTemplate = Mockito.mock(TransactionTemplate.class);
    private final NotificationService notificationService = Mockito.mock(NotificationService.class);
    private final TaskRecordService taskRecordService = Mockito.mock(TaskRecordService.class);
    private final SafeUrlValidator safeUrlValidator = Mockito.mock(SafeUrlValidator.class);
    private final BoundedFileTreeScanner fileTreeScanner = fileTreeScanner();
    private final FileIngressSafetyService ingressSafetyService = Mockito.mock(FileIngressSafetyService.class);
    private final FileIngressLifecycleService ingressLifecycleService =
            Mockito.mock(FileIngressLifecycleService.class);

    private final OfflineDownloadExecutionService service = new OfflineDownloadExecutionService(
            offlineTaskRepository, fileNodeRepository, fileObjectRepository,
            storageQuotaService, objectStorageClient, domainEventPublisher, postProcessingTaskService,
            sourceResolver, offlineDownloadGateway, objectStorageBuckets,
            transactionTemplate, notificationService, taskRecordService, safeUrlValidator,
            fileTreeScanner, ingressSafetyService, ingressLifecycleService
    );

    private static BoundedFileTreeScanner fileTreeScanner() {
        return new BoundedFileTreeScanner(new FileTransferLimitsProperties());
    }

    @BeforeEach
    void setUpTaskClaim() {
        Mockito.when(taskRecordService.claimForExecution(Mockito.any(UUID.class), Mockito.any(String.class)))
                .thenReturn(true);
        Mockito.when(objectStorageBuckets.quarantine()).thenReturn("file-quarantine");
        Mockito.when(objectStorageBuckets.userFiles()).thenReturn("user-files");
        Mockito.when(ingressLifecycleService.open(Mockito.any())).thenReturn(UUID.randomUUID());
        Mockito.when(ingressSafetyService.inspect(
                        Mockito.any(ObjectStorageKey.class),
                        Mockito.anyLong(),
                        Mockito.anyString(),
                        Mockito.any(UUID.class)
                ))
                .thenReturn(new InspectionResult(Status.CLEAN, "文件安全", "0".repeat(64)));
    }

    @Test
    void execute_createsDownloadTask() {
        // 模拟 TransactionTemplate 直接执行回调（markRunning 使用）
        Mockito.when(transactionTemplate.execute(any())).thenAnswer(invocation -> {
            TransactionCallback<?> callback = invocation.getArgument(0);
            return callback.doInTransaction(null);
        });

        // 模拟 aria2 下载根目录
        Mockito.when(offlineDownloadGateway.downloadRoot())
                .thenReturn(Path.of(System.getProperty("java.io.tmpdir")));
        Mockito.when(offlineDownloadGateway.pollIntervalSeconds()).thenReturn(1);

        // 构造 QUEUED 状态的任务
        DownloadOfflineTask task = new DownloadOfflineTask();
        task.setId(TASK_ID);
        task.setOwnerUserId(UUID.randomUUID());
        task.setSourceUri("https://example.com/file.zip");
        task.setFileName("file.zip");
        task.setStatus(TaskStatus.QUEUED.getValue());
        Mockito.when(offlineTaskRepository.findById(TASK_ID)).thenReturn(Optional.of(task));
        Mockito.when(offlineTaskRepository.save(any())).thenAnswer(inv -> inv.getArgument(0));

        // 模拟源地址解析成功
        ResolvedSource resolvedSource =
                new ResolvedSource(
                        SourceKind.HTTP,
                        URI.create("https://example.com/file.zip")
                );
        Mockito.when(sourceResolver.resolve("https://example.com/file.zip")).thenReturn(resolvedSource);

        // 模拟 aria2 提交成功
        Mockito.when(offlineDownloadGateway.submitUri(any(), any())).thenReturn("gid123");

        // 模拟 Aria2 状态查询返回完成
        TaskSnapshot completedStatus = new TaskSnapshot(
                "complete", 1024L, 1024L, 0L, List.of(), null, null
        );
        Mockito.when(offlineDownloadGateway.queryStatus("gid123")).thenReturn(completedStatus);

        // 执行下载任务（不抛异常即为成功进入执行流程）
        OfflineDownloadRequestedEvent event = new OfflineDownloadRequestedEvent(TASK_ID);
        service.execute(event);

        // 验证源地址解析被调用（SSRF 验证入口）
        Mockito.verify(sourceResolver, Mockito.atLeastOnce()).resolve("https://example.com/file.zip");
    }

    @Test
    void execute_skipsDownloadWhenTaskWasClaimedByAnotherConsumer() {
        Mockito.when(transactionTemplate.execute(any())).thenAnswer(invocation -> {
            TransactionCallback<?> callback = invocation.getArgument(0);
            return callback.doInTransaction(null);
        });
        DownloadOfflineTask task = new DownloadOfflineTask();
        task.setId(TASK_ID);
        task.setStatus(TaskStatus.QUEUED.getValue());
        Mockito.when(offlineTaskRepository.findById(TASK_ID)).thenReturn(Optional.of(task));
        Mockito.when(taskRecordService.claimForExecution(Mockito.any(UUID.class), Mockito.eq("DOWNLOADING")))
                .thenReturn(false);

        service.execute(new OfflineDownloadRequestedEvent(TASK_ID));

        Mockito.verifyNoInteractions(sourceResolver);
        Mockito.verify(offlineTaskRepository, Mockito.never()).save(any());
    }

    @Test
    void execute_throwsWhenSourceUrlInvalid() {
        // 模拟 TransactionTemplate 直接执行回调（markRunning 使用）
        Mockito.when(transactionTemplate.execute(any())).thenAnswer(invocation -> {
            TransactionCallback<?> callback = invocation.getArgument(0);
            return callback.doInTransaction(null);
        });

        // 模拟 aria2 下载根目录
        Mockito.when(offlineDownloadGateway.downloadRoot())
                .thenReturn(Path.of(System.getProperty("java.io.tmpdir")));

        // 构造 QUEUED 状态的任务，使用 localhost 地址触发 SSRF 验证
        DownloadOfflineTask task = new DownloadOfflineTask();
        task.setId(TASK_ID);
        task.setOwnerUserId(UUID.randomUUID());
        task.setSourceUri("http://localhost/secret");
        task.setFileName("test.txt");
        task.setStatus(TaskStatus.QUEUED.getValue());
        Mockito.when(offlineTaskRepository.findById(TASK_ID)).thenReturn(Optional.of(task));
        Mockito.when(offlineTaskRepository.save(any())).thenAnswer(inv -> inv.getArgument(0));

        // 模拟 SSRF 验证拒绝 localhost 地址
        Mockito.when(sourceResolver.resolve("http://localhost/secret"))
                .thenThrow(new BusinessException(ErrorCode.BAD_REQUEST, "URL 不能指向本地或内网地址"));

        // execute 内部捕获异常并标记任务失败，不向外抛出
        OfflineDownloadRequestedEvent event = new OfflineDownloadRequestedEvent(TASK_ID);
        service.execute(event);

        // 验证 SSRF 验证被触发
        Mockito.verify(sourceResolver).resolve("http://localhost/secret");
        // 验证未提交到 aria2
        Mockito.verify(offlineDownloadGateway, Mockito.never()).submitUri(any(), any());
    }
}
