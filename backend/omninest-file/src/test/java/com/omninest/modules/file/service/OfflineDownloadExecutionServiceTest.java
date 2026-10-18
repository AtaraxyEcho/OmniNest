package com.omninest.modules.file.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;

import com.omninest.common.download.OfflineDownloadGateway;
import com.omninest.common.download.OfflineDownloadGateway.DownloadedFile;
import com.omninest.common.download.OfflineDownloadGateway.TaskSnapshot;
import com.omninest.common.download.OfflineDownloadSourceResolver;
import com.omninest.common.download.OfflineDownloadSourceResolver.ResolvedSource;
import com.omninest.common.download.OfflineDownloadSourceResolver.SourceKind;
import com.omninest.common.download.TorrentAddressValidator;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.messaging.DomainEventPublisher;
import com.omninest.common.security.SafeUrlValidator;
import com.omninest.common.storage.ObjectStorageBuckets;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.common.storage.ObjectStorageKey;
import com.omninest.modules.file.config.FileTransferLimitsProperties;
import com.omninest.modules.file.domain.DownloadOfflineTask;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.FileObject;
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
import java.io.IOException;
import java.net.URI;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.Consumer;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.InOrder;
import org.mockito.Mockito;
import org.springframework.transaction.TransactionStatus;
import org.springframework.transaction.support.TransactionCallback;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;
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
    private final TorrentAddressValidator torrentAddressValidator = Mockito.mock(TorrentAddressValidator.class);
    private final BoundedFileTreeScanner fileTreeScanner = fileTreeScanner();
    private final FileIngressSafetyService ingressSafetyService = Mockito.mock(FileIngressSafetyService.class);
    private final FileIngressLifecycleService ingressLifecycleService =
            Mockito.mock(FileIngressLifecycleService.class);
    private final SharedSpaceQuotaService sharedSpaceQuotaService =
            Mockito.mock(SharedSpaceQuotaService.class);

    private final OfflineDownloadExecutionService service = new OfflineDownloadExecutionService(
            offlineTaskRepository, fileNodeRepository, fileObjectRepository,
            storageQuotaService, sharedSpaceQuotaService, objectStorageClient, domainEventPublisher, postProcessingTaskService,
            sourceResolver, offlineDownloadGateway, objectStorageBuckets,
            transactionTemplate, notificationService, taskRecordService, safeUrlValidator,
            torrentAddressValidator,
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
                        Mockito.any(),
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

    @Test
    void importKeepsObjectIoOutsideTheMetadataTransaction() throws IOException {
        List<String> trace = new ArrayList<>();
        Path downloadRoot = Files.createTempDirectory("offline-import-tx");
        DownloadOfflineTask task = stubImportRun(trace, downloadRoot);

        service.execute(new OfflineDownloadRequestedEvent(TASK_ID));

        assertThat(task.getStatus()).isEqualTo(TaskStatus.COMPLETED.getValue());
        // 三段式入库的顺序与事务边界：条目前缀标记调用发生时线程上是否存在数据库事务。
        // 阶段 A 的对象上传、ClamAV 扫描与桶间复制必须在事务外；阶段 B 只写目录、内容与配额；
        // 阶段 C 的事件投递必须排在 afterCompletion（入库可用、隔离对象清理）之后。
        assertThat(operations(trace)).containsExactly(
                "no-tx:reserve",
                "no-tx:putObject", "no-tx:inspect", "no-tx:copyObject",
                "no-tx:putObject", "no-tx:inspect", "no-tx:copyObject",
                "in-tx:saveFileNode:series",
                "in-tx:saveFileNode:S01",
                "in-tx:saveFileObject", "in-tx:saveFileNode:a.mkv",
                "in-tx:saveFileObject", "in-tx:saveFileNode:b.mkv",
                "in-tx:settleReservation",
                "in-tx:notify",
                "no-tx:markAvailable", "no-tx:removeObject:file-quarantine",
                "no-tx:markAvailable", "no-tx:removeObject:file-quarantine",
                "no-tx:publishTask", "no-tx:publishTask");
    }

    @Test
    void importDiscardsStagedObjectsWhenScanFailsHalfway() throws IOException {
        List<String> trace = new ArrayList<>();
        Path downloadRoot = Files.createTempDirectory("offline-import-discard");
        DownloadOfflineTask task = stubImportRun(trace, downloadRoot);
        AtomicInteger scans = new AtomicInteger();
        // 用 doAnswer 覆盖既有的 inspect 桩：when(...) 会真实调用一次 mock，把上一条桩的 answer 也记进 trace。
        Mockito.doAnswer(invocation -> {
                    trace.add(tag("inspect"));
                    if (scans.incrementAndGet() > 1) {
                        throw new BusinessException(ErrorCode.FILE_SECURITY_REJECTED, "文件未通过安全扫描");
                    }
                    return new InspectionResult(Status.CLEAN, "文件安全", "0".repeat(64));
                })
                .when(ingressSafetyService)
                .inspect(any(), anyLong(), any(), any(), any());

        service.execute(new OfflineDownloadRequestedEvent(TASK_ID));

        assertThat(task.getStatus()).isEqualTo(TaskStatus.FAILED.getValue());
        // 事务尚未开启就失败，本批已复制到正式桶的对象无人回滚：必须就地删除，隔离桶交给回收器。
        assertThat(operations(trace)).containsExactly(
                "no-tx:reserve",
                "no-tx:putObject", "no-tx:inspect", "no-tx:copyObject",
                "no-tx:putObject", "no-tx:inspect",
                "no-tx:markFailed", "no-tx:markFailed", "no-tx:removeObject:user-files",
                "in-tx:releaseReservation",
                "no-tx:notify");
        Mockito.verify(fileNodeRepository, Mockito.never()).save(any());
        Mockito.verify(fileObjectRepository, Mockito.never()).save(any());
    }

    /**
     * 装配入库链路协作依赖：两个暂存文件、事务按 Spring 时序代跑，每次调用记录当时的事务状态。
     */
    private DownloadOfflineTask stubImportRun(List<String> trace, Path downloadRoot) throws IOException {
        Path taskDirectory = downloadRoot.resolve(TASK_ID.toString());
        Files.createDirectories(taskDirectory.resolve("S01"));
        Files.writeString(taskDirectory.resolve("S01/a.mkv"), "aaaa");
        Files.writeString(taskDirectory.resolve("S01/b.mkv"), "bbbb");

        Mockito.when(transactionTemplate.execute(any()))
                .thenAnswer(invocation -> runInFakeTransaction(invocation.getArgument(0), trace));
        Mockito.doAnswer(invocation -> runInFakeTransaction(status -> {
            invocation.<Consumer<TransactionStatus>>getArgument(0).accept(status);
            return null;
        }, trace)).when(transactionTemplate).executeWithoutResult(any());
        Mockito.when(offlineDownloadGateway.downloadRoot()).thenReturn(downloadRoot);
        Mockito.when(offlineDownloadGateway.pollIntervalSeconds()).thenReturn(1);
        Mockito.when(offlineDownloadGateway.submitUri(any(), any())).thenReturn("gid1");
        Mockito.when(offlineDownloadGateway.queryStatus("gid1")).thenReturn(new TaskSnapshot(
                "complete", 8L, 8L, 0L, List.of(), "series", null));
        String magnet = "magnet:?xt=urn:btih:0000000000000000000000000000000000000000";
        Mockito.when(sourceResolver.resolve(magnet))
                .thenReturn(new ResolvedSource(SourceKind.MAGNET, URI.create(magnet)));

        DownloadOfflineTask task = new DownloadOfflineTask();
        task.setId(TASK_ID);
        task.setOwnerUserId(UUID.randomUUID());
        task.setSourceUri(magnet);
        task.setFileName("series");
        task.setStatus(TaskStatus.QUEUED.getValue());
        Mockito.when(offlineTaskRepository.findById(TASK_ID)).thenReturn(Optional.of(task));
        Mockito.when(offlineTaskRepository.save(any())).thenAnswer(invocation -> invocation.getArgument(0));

        Mockito.when(storageQuotaService.reserve(any(), any(), any(), anyLong(), any()))
                .thenAnswer(invocation -> {
                    trace.add(tag("reserve"));
                    return UUID.randomUUID();
                });
        Mockito.doAnswer(invocation -> {
            trace.add(tag("settleReservation"));
            return null;
        }).when(storageQuotaService).settleReservation(any(), any(), anyLong());
        Mockito.doAnswer(invocation -> {
            trace.add(tag("releaseReservation"));
            return null;
        }).when(storageQuotaService).releaseReservation(any(), any());
        Mockito.doAnswer(invocation -> {
            trace.add(tag("putObject"));
            return null;
        }).when(objectStorageClient).putObject(any(ObjectStorageKey.class), any(Path.class), any());
        Mockito.doAnswer(invocation -> {
            trace.add(tag("copyObject"));
            return null;
        }).when(objectStorageClient).copyObject(any(ObjectStorageKey.class), any(ObjectStorageKey.class));
        Mockito.doAnswer(invocation -> {
            trace.add(tag("removeObject:" + ((ObjectStorageKey) invocation.getArgument(0)).bucket()));
            return null;
        }).when(objectStorageClient).removeObject(any(ObjectStorageKey.class));
        Mockito.when(ingressSafetyService.inspect(any(), anyLong(), any(), any(), any()))
                .thenAnswer(invocation -> {
                    trace.add(tag("inspect"));
                    return new InspectionResult(Status.CLEAN, "文件安全", "0".repeat(64));
                });
        Mockito.doAnswer(invocation -> {
            trace.add(tag("markAvailable"));
            return null;
        }).when(ingressLifecycleService).markAvailable(any(), any());
        Mockito.doAnswer(invocation -> {
            trace.add(tag("markFailed"));
            return null;
        }).when(ingressLifecycleService).markFailed(any(), Mockito.anyBoolean(), any(), any());
        Mockito.when(fileObjectRepository.save(any())).thenAnswer(invocation -> {
            FileObject object = invocation.getArgument(0);
            object.setId(UUID.randomUUID());
            trace.add(tag("saveFileObject"));
            return object;
        });
        Mockito.when(fileNodeRepository.save(any())).thenAnswer(invocation -> {
            FileNode node = invocation.getArgument(0);
            node.setId(UUID.randomUUID());
            trace.add(tag("saveFileNode:" + node.getName()));
            return node;
        });
        Mockito.doAnswer(invocation -> {
            trace.add(tag("publishTask"));
            return null;
        }).when(domainEventPublisher).publishTask(any(), any());
        Mockito.doAnswer(invocation -> {
            trace.add(tag("notify"));
            return null;
        }).when(notificationService).notifyOrLog(any(), any(), any(), any(), any());
        return task;
    }

    @Test
    void aria2IsNeverToldToParseDownloadedTorrentsItself() throws IOException {
        Path downloadRoot = Files.createTempDirectory("offline-follow-torrent");
        Mockito.when(transactionTemplate.execute(any())).thenAnswer(invocation -> {
            TransactionCallback<?> callback = invocation.getArgument(0);
            return callback.doInTransaction(null);
        });
        Mockito.when(offlineDownloadGateway.downloadRoot()).thenReturn(downloadRoot);
        Mockito.when(offlineDownloadGateway.pollIntervalSeconds()).thenReturn(1);
        String magnet = "magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567";
        Mockito.when(sourceResolver.resolve(magnet))
                .thenReturn(new ResolvedSource(SourceKind.MAGNET, URI.create(magnet)));
        Mockito.when(offlineDownloadGateway.submitUri(any(), any())).thenReturn("gid1");
        Mockito.when(offlineDownloadGateway.queryStatus("gid1")).thenReturn(new TaskSnapshot(
                "complete", 8L, 8L, 0L, List.of(), "probe", null));
        DownloadOfflineTask task = newQueuedTask(magnet);
        Mockito.when(offlineTaskRepository.findById(TASK_ID)).thenReturn(Optional.of(task));
        Mockito.when(offlineTaskRepository.save(any())).thenAnswer(invocation -> invocation.getArgument(0));

        service.execute(new OfflineDownloadRequestedEvent(TASK_ID));

        // 实测过：true 与 mem 都会让 aria2 解析取回的内容并立刻回连其中内嵌的 url-list / announce，
        // 而那批地址从未过我们的闸门。展开必须由我们在校验之后自己提交。
        @SuppressWarnings("unchecked")
        ArgumentCaptor<Map<String, Object>> options = ArgumentCaptor.forClass(Map.class);
        Mockito.verify(offlineDownloadGateway).submitUri(Mockito.eq(magnet), options.capture());
        assertThat(options.getValue()).containsEntry("follow-torrent", "false");
    }

    @Test
    void magnetIsFirstAllowedToFetchOnlyTheMetadata() throws IOException {
        Path downloadRoot = Files.createTempDirectory("offline-magnet-metadata");
        Mockito.when(transactionTemplate.execute(any())).thenAnswer(invocation -> {
            TransactionCallback<?> callback = invocation.getArgument(0);
            return callback.doInTransaction(null);
        });
        Mockito.when(offlineDownloadGateway.downloadRoot()).thenReturn(downloadRoot);
        Mockito.when(offlineDownloadGateway.pollIntervalSeconds()).thenReturn(1);
        String magnet = "magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567";
        Mockito.when(sourceResolver.resolve(magnet))
                .thenReturn(new ResolvedSource(SourceKind.MAGNET, URI.create(magnet)));
        Mockito.when(offlineDownloadGateway.submitUri(any(), any())).thenReturn("gid1");
        Mockito.when(offlineDownloadGateway.queryStatus("gid1")).thenReturn(new TaskSnapshot(
                "complete", 0L, 0L, 0L, List.of(), "probe", null));
        DownloadOfflineTask task = newQueuedTask(magnet);
        Mockito.when(offlineTaskRepository.findById(TASK_ID)).thenReturn(Optional.of(task));
        Mockito.when(offlineTaskRepository.save(any())).thenAnswer(invocation -> invocation.getArgument(0));

        service.execute(new OfflineDownloadRequestedEvent(TASK_ID));

        // 磁力链接里能静态校验的只有 xt/an/tr/ws：种子的 announce 与 url-list 要等元数据到手才存在。
        // 第一趟必须停在元数据，并把种子落盘交给我们校验，内容下载由第二趟重新提交。
        @SuppressWarnings("unchecked")
        ArgumentCaptor<Map<String, Object>> options = ArgumentCaptor.forClass(Map.class);
        Mockito.verify(offlineDownloadGateway).submitUri(Mockito.eq(magnet), options.capture());
        assertThat(options.getValue())
                .containsEntry("bt-metadata-only", "true")
                .containsEntry("bt-save-metadata", "true");
    }

    @Test
    void torrentShapedDirectLinkIsValidatedBeforeItIsExpanded() throws IOException {
        Path taskDirectory = Files.createTempDirectory("offline-torrent-expand");
        Path payload = taskDirectory.resolve("payload");
        Files.writeString(payload, "d8:announce0:e");
        Mockito.when(transactionTemplate.execute(any())).thenAnswer(invocation -> {
            TransactionCallback<?> callback = invocation.getArgument(0);
            return callback.doInTransaction(null);
        });
        DownloadOfflineTask task = newQueuedTask("https://example.com/payload");
        Mockito.when(offlineTaskRepository.findById(TASK_ID)).thenReturn(Optional.of(task));
        Mockito.when(offlineTaskRepository.save(any())).thenAnswer(invocation -> invocation.getArgument(0));
        Mockito.when(torrentAddressValidator.looksLikeTorrent(any())).thenReturn(true);
        Mockito.doThrow(new BusinessException(ErrorCode.FILE_SECURITY_REJECTED, "种子内嵌地址不允许"))
                .when(torrentAddressValidator)
                .validate(any());

        assertThatThrownBy(() -> service.expandHttpTorrentPayload(
                task,
                new ResolvedSource(SourceKind.HTTP, URI.create("https://example.com/payload")),
                taskDirectory,
                List.of(payload)))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("种子内嵌地址不允许");

        // 校验没过就不许把种子交给下载器：一次展开请求都不能发出去。
        Mockito.verifyNoInteractions(offlineDownloadGateway);
    }

    @Test
    void validatedTorrentLinkIsExpandedIntoItsOwnContentsAndTheSeedIsNotImported() throws IOException {
        Path taskDirectory = Files.createTempDirectory("offline-torrent-expanded");
        Path payload = taskDirectory.resolve("payload");
        Files.writeString(payload, "d8:announce0:e");
        Path video = taskDirectory.resolve("episode.mkv");
        Files.writeString(video, "video-bytes");
        Mockito.when(transactionTemplate.execute(any())).thenAnswer(invocation -> {
            TransactionCallback<?> callback = invocation.getArgument(0);
            return callback.doInTransaction(null);
        });
        Mockito.when(offlineDownloadGateway.pollIntervalSeconds()).thenReturn(1);
        DownloadOfflineTask task = newQueuedTask("https://example.com/payload");
        Mockito.when(offlineTaskRepository.findById(TASK_ID)).thenReturn(Optional.of(task));
        Mockito.when(offlineTaskRepository.save(any())).thenAnswer(invocation -> invocation.getArgument(0));
        Mockito.when(torrentAddressValidator.looksLikeTorrent(any())).thenReturn(true);
        Mockito.when(offlineDownloadGateway.submitTorrent(any(), any())).thenReturn("gid2");
        Mockito.when(offlineDownloadGateway.queryStatus("gid2")).thenReturn(new TaskSnapshot(
                "complete", 11L, 11L, 0L,
                List.of(new DownloadedFile(video.toString(), true)), "episode", null));

        List<Path> result = service.expandHttpTorrentPayload(
                task,
                new ResolvedSource(SourceKind.HTTP, URI.create("https://example.com/payload")),
                taskDirectory,
                List.of(payload));

        InOrder order = Mockito.inOrder(torrentAddressValidator, offlineDownloadGateway);
        order.verify(torrentAddressValidator).validate(any());
        order.verify(offlineDownloadGateway).submitTorrent(any(), any());
        // 入库的是种子内容，不是那枚种子本体——与改参数之前的可见结果一致。
        assertThat(result).containsExactly(video);
    }

    /**
     * 磁力第一趟取回的元数据没过闸门时，一个下载请求都不许发出。
     */
    @Test
    void magnetMetadataIsValidatedBeforeItsContentsAreDownloaded() throws IOException {
        String magnet = "magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567";
        Path taskDirectory = Files.createTempDirectory("offline-magnet-rejected");
        Path metadata = taskDirectory.resolve("0123456789abcdef0123456789abcdef01234567.torrent");
        Files.writeString(metadata, "d8:announce0:e");
        Mockito.when(transactionTemplate.execute(any())).thenAnswer(invocation -> {
            TransactionCallback<?> callback = invocation.getArgument(0);
            return callback.doInTransaction(null);
        });
        DownloadOfflineTask task = newQueuedTask(magnet);
        Mockito.when(offlineTaskRepository.findById(TASK_ID)).thenReturn(Optional.of(task));
        Mockito.when(offlineTaskRepository.save(any())).thenAnswer(invocation -> invocation.getArgument(0));
        Mockito.when(torrentAddressValidator.looksLikeTorrent(any())).thenReturn(true);
        Mockito.doThrow(new BusinessException(ErrorCode.FILE_SECURITY_REJECTED, "种子内嵌地址不允许"))
                .when(torrentAddressValidator)
                .validate(any());

        assertThatThrownBy(() -> service.expandMagnetMetadata(
                task,
                new ResolvedSource(SourceKind.MAGNET, URI.create(magnet)),
                taskDirectory,
                List.of(metadata)))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("种子内嵌地址不允许");

        Mockito.verifyNoInteractions(offlineDownloadGateway);
    }

    @Test
    void validatedMagnetMetadataExpandsIntoItsContentsAndTheMetadataIsNotImported() throws IOException {
        String magnet = "magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567";
        Path taskDirectory = Files.createTempDirectory("offline-magnet-expanded");
        Path metadata = taskDirectory.resolve("0123456789abcdef0123456789abcdef01234567.torrent");
        Files.writeString(metadata, "d8:announce0:e");
        Path video = taskDirectory.resolve("episode.mkv");
        Files.writeString(video, "video-bytes");
        Mockito.when(transactionTemplate.execute(any())).thenAnswer(invocation -> {
            TransactionCallback<?> callback = invocation.getArgument(0);
            return callback.doInTransaction(null);
        });
        Mockito.when(offlineDownloadGateway.pollIntervalSeconds()).thenReturn(1);
        DownloadOfflineTask task = newQueuedTask(magnet);
        Mockito.when(offlineTaskRepository.findById(TASK_ID)).thenReturn(Optional.of(task));
        Mockito.when(offlineTaskRepository.save(any())).thenAnswer(invocation -> invocation.getArgument(0));
        Mockito.when(torrentAddressValidator.looksLikeTorrent(any())).thenReturn(true);
        Mockito.when(offlineDownloadGateway.submitTorrent(any(), any())).thenReturn("gid2");
        Mockito.when(offlineDownloadGateway.queryStatus("gid2")).thenReturn(new TaskSnapshot(
                "complete", 11L, 11L, 0L,
                List.of(new DownloadedFile(video.toString(), true)), "episode", null));

        List<Path> result = service.expandMagnetMetadata(
                task,
                new ResolvedSource(SourceKind.MAGNET, URI.create(magnet)),
                taskDirectory,
                List.of(metadata));

        InOrder order = Mockito.inOrder(torrentAddressValidator, offlineDownloadGateway);
        order.verify(torrentAddressValidator).validate(any());
        @SuppressWarnings("unchecked")
        ArgumentCaptor<Map<String, Object>> options = ArgumentCaptor.forClass(Map.class);
        order.verify(offlineDownloadGateway).submitTorrent(any(), options.capture());
        // 第二趟我们已持有校验过的种子内容：不再让下载器另存元数据，否则会多出一枚混进入库的种子文件。
        assertThat(options.getValue())
                .containsEntry("bt-save-metadata", "false")
                .containsEntry("bt-metadata-only", "false")
                .containsEntry("follow-torrent", "false");
        assertThat(result).containsExactly(video);
    }

    private DownloadOfflineTask newQueuedTask(String sourceUri) {
        DownloadOfflineTask task = new DownloadOfflineTask();
        task.setId(TASK_ID);
        task.setOwnerUserId(UUID.randomUUID());
        task.setSourceUri(sourceUri);
        task.setFileName("probe");
        task.setStatus(TaskStatus.QUEUED.getValue());
        return task;
    }

    /**
     * 丢弃事务标记，只保留带事务状态前缀的业务调用序列。
     */
    private static List<String> operations(List<String> trace) {
        return trace.stream().filter(entry -> !entry.startsWith("tx-")).toList();
    }

    /**
     * 用真实的事务同步机制代跑 TransactionTemplate：提交点触发 afterCommit，
     * 同步清理并归还连接之后才触发 afterCompletion，与 Spring 的时序一致。
     */
    private <T> T runInFakeTransaction(TransactionCallback<T> callback, List<String> trace) {
        trace.add("tx-begin");
        TransactionSynchronizationManager.setActualTransactionActive(true);
        TransactionSynchronizationManager.initSynchronization();
        List<TransactionSynchronization> synchronizations = List.of();
        boolean committed = false;
        try {
            T result = callback.doInTransaction(null);
            synchronizations = List.copyOf(TransactionSynchronizationManager.getSynchronizations());
            synchronizations.forEach(TransactionSynchronization::afterCommit);
            committed = true;
            return result;
        } catch (RuntimeException exception) {
            synchronizations = List.copyOf(TransactionSynchronizationManager.getSynchronizations());
            throw exception;
        } finally {
            TransactionSynchronizationManager.clearSynchronization();
            TransactionSynchronizationManager.setActualTransactionActive(false);
            trace.add(committed ? "tx-commit" : "tx-rollback");
            int status = committed
                    ? TransactionSynchronization.STATUS_COMMITTED
                    : TransactionSynchronization.STATUS_ROLLED_BACK;
            synchronizations.forEach(synchronization -> synchronization.afterCompletion(status));
        }
    }

    /**
     * 记录调用发生时线程上是否存在数据库事务。
     */
    private static String tag(String operation) {
        return (TransactionSynchronizationManager.isActualTransactionActive() ? "in-tx:" : "no-tx:") + operation;
    }
}
