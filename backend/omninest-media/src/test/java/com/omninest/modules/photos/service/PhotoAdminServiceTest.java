package com.omninest.modules.photos.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyMap;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.cache.ReadThroughCache;
import com.omninest.common.messaging.QueueNames;
import com.omninest.common.sync.SyncScope;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.dto.FileDescriptor;
import com.omninest.modules.file.service.FileMetadataQueryService;
import com.omninest.modules.file.service.FilePostProcessingTaskService;
import com.omninest.modules.file.service.FileQueryService;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.notification.port.NotificationPublisher;
import com.omninest.modules.photos.domain.PhotoItem;
import com.omninest.modules.photos.domain.PhotoScanJob;
import com.omninest.modules.photos.repository.PhotoItemRepository;
import com.omninest.modules.photos.repository.PhotoScanJobRepository;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskHeartbeatRunner;
import com.omninest.modules.task.service.TaskRecordService;
import com.omninest.modules.task.domain.TaskStatus;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Collection;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.IntSupplier;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.InOrder;
import org.springframework.data.domain.PageRequest;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionStatus;

/**
 * 照片扫描收尾事务边界测试。
 *
 * <p>同步事件记录器要求外层事务（MANDATORY 传播），executeScanJob 本体刻意
 * 无事务，失效事件与终态保存必须在独立短事务内原子提交（D-009）。</p>
 *
 * @author OmniNest
 */
class PhotoAdminServiceTest {

    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID JOB_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");

    private final PhotoScanJobRepository scanJobRepository = mock(PhotoScanJobRepository.class);
    private final PhotoItemRepository photoItemRepository = mock(PhotoItemRepository.class);
    private final FileMetadataQueryService fileMetadataQueryService = mock(FileMetadataQueryService.class);
    private final PhotoFileDetector fileDetector = mock(PhotoFileDetector.class);
    private final PhotoInputGuard inputGuard = mock(PhotoInputGuard.class);
    private final PhotoSourceFileService sourceFileService = mock(PhotoSourceFileService.class);
    private final PhotoExifExtractor exifExtractor = mock(PhotoExifExtractor.class);
    private final PhotoThumbnailService thumbnailService = mock(PhotoThumbnailService.class);
    private final NotificationPublisher notificationService = mock(NotificationPublisher.class);
    private final TaskDispatchService taskDispatchService = mock(TaskDispatchService.class);
    private final PhotoRawPreviewService rawPreviewService = mock(PhotoRawPreviewService.class);
    private final PhotosRuntimeConfigService photosRuntimeConfigService = mock(PhotosRuntimeConfigService.class);
    private final FileQueryService fileQueryService = mock(FileQueryService.class);
    private final PhotoGeoService photoGeoService = mock(PhotoGeoService.class);
    private final PhotoAiTaskService photoAiTaskService = mock(PhotoAiTaskService.class);
    private final TaskRecordService taskRecordService = mock(TaskRecordService.class);
    private final TaskHeartbeatRunner taskHeartbeatRunner = mock(TaskHeartbeatRunner.class);
    private final FilePostProcessingTaskService filePostProcessingTaskService =
            mock(FilePostProcessingTaskService.class);
    private final MediaSyncEventService syncEventService = mock(MediaSyncEventService.class);
    private final ReadThroughCache readThroughCache = mock(ReadThroughCache.class);
    private final PlatformTransactionManager transactionManager = mock(PlatformTransactionManager.class);
    private final PhotoAdminService service = new PhotoAdminService(
            scanJobRepository,
            photoItemRepository,
            fileMetadataQueryService,
            fileDetector,
            inputGuard,
            sourceFileService,
            exifExtractor,
            thumbnailService,
            notificationService,
            taskDispatchService,
            rawPreviewService,
            photosRuntimeConfigService,
            fileQueryService,
            photoGeoService,
            photoAiTaskService,
            taskRecordService,
            taskHeartbeatRunner,
            filePostProcessingTaskService,
            syncEventService,
            readThroughCache,
            transactionManager
    );

    @BeforeEach
    void setUp() {
        service.initTransactionTemplate();
        when(taskRecordService.claimForExecution(JOB_ID, "SCANNING")).thenReturn(true);
        when(fileMetadataQueryService.listOwnedImagesPage(
                eq(OWNER_ID), any(UUID.class), anyInt())).thenReturn(List.of());
        when(taskHeartbeatRunner.start(eq(JOB_ID), any(IntSupplier.class)))
                .thenReturn(mock(TaskHeartbeatRunner.Heartbeat.class));
        when(scanJobRepository.save(any(PhotoScanJob.class))).thenAnswer(invocation -> {
            PhotoScanJob saved = invocation.getArgument(0);
            // 模拟 Hibernate merge：每次保存后 version 前进，返回实例携带新版本号。
            saved.setVersion(saved.getVersion() + 1);
            return saved;
        });
        when(transactionManager.getTransaction(any())).thenReturn(mock(TransactionStatus.class));
    }

    @Test
    void scanRespectsConfiguredConcurrency() {
        service.scanConcurrency = 1;
        PhotoScanJob job = queuedJob();
        when(scanJobRepository.findById(JOB_ID)).thenReturn(Optional.of(job));
        when(fileMetadataQueryService.countOwnedImages(OWNER_ID)).thenReturn(3L);
        when(fileMetadataQueryService.listOwnedImagesPage(
                eq(OWNER_ID), any(UUID.class), anyInt())).thenReturn(List.of(
                descriptor("p1.jpg"), descriptor("p2.jpg"), descriptor("p3.jpg")));
        AtomicInteger active = new AtomicInteger();
        AtomicInteger maxActive = new AtomicInteger();
        when(transactionManager.getTransaction(any())).thenAnswer(invocation -> {
            int current = active.incrementAndGet();
            maxActive.accumulateAndGet(current, Math::max);
            try {
                Thread.sleep(30);
            } finally {
                active.decrementAndGet();
            }
            return mock(TransactionStatus.class);
        });

        service.executeScanJob(JOB_ID, OWNER_ID);

        assertThat(maxActive.get()).isLessThanOrEqualTo(1);
    }

    @Test
    void executeScanJobInvalidatesSyncEventInsideTransaction() {
        PhotoScanJob job = queuedJob();
        when(scanJobRepository.findById(JOB_ID)).thenReturn(Optional.of(job));

        service.executeScanJob(JOB_ID, OWNER_ID);

        // 失效事件必须发生在独立短事务内：getTransaction -> invalidate -> commit，
        // 修复前裸调 invalidate 无活动事务，触发 IllegalTransactionStateException。
        InOrder inOrder = inOrder(transactionManager, syncEventService);
        inOrder.verify(transactionManager).getTransaction(any());
        inOrder.verify(syncEventService).invalidate(
                eq(OWNER_ID), eq(SyncScope.PHOTOS), eq("PHOTO_LIBRARY"), anyMap());
        inOrder.verify(transactionManager).commit(any());
        assertThat(job.getStatus()).isEqualTo(TaskStatus.COMPLETED.getValue());
        assertThat(job.getVersion()).isEqualTo(2L);
    }

    @Test
    void executeScanJobFailurePathRewritesTerminalStateOnReloadedEntity() {
        PhotoScanJob job = queuedJob();
        when(scanJobRepository.findById(JOB_ID)).thenReturn(Optional.of(job));
        when(fileMetadataQueryService.listOwnedImagesPage(
                eq(OWNER_ID), any(UUID.class), anyInt()))
                .thenThrow(new IllegalStateException("元数据查询不可用"));

        assertThatThrownBy(() -> service.executeScanJob(JOB_ID, OWNER_ID))
                .isInstanceOf(IllegalStateException.class);

        // 失败收尾按 id 重新加载最新实体后写 FAILED，任务行不得停留在 RUNNING。
        verify(scanJobRepository, times(2)).findById(JOB_ID);
        assertThat(job.getStatus()).isEqualTo(TaskStatus.FAILED.getValue());
        verify(taskRecordService).markFailed(eq(JOB_ID), any(), any());
        verify(syncEventService, never()).invalidate(any(), any(), any(), anyMap());
    }

    @Test
    void createScanJobUsesOutboxDispatch() {
        PhotoScanJob saved = queuedJob();
        when(scanJobRepository.save(any(PhotoScanJob.class))).thenAnswer(invocation -> invocation.getArgument(0));

        var dto = service.createScanJob(OWNER_ID);

        assertThat(dto.status()).isEqualTo(TaskStatus.QUEUED.getValue());
        verify(taskDispatchService).enqueue(
                eq(dto.id()),
                eq(QueueNames.TASK_EXCHANGE),
                eq(QueueNames.PHOTO_SCAN_ROUTING_KEY),
                any());
    }

    @Test
    void thumbnailRegenerationWalksPagesByCursorAndReportsTheRegeneratedCount() {
        UUID taskId = UUID.randomUUID();
        UUID photoId = UUID.randomUUID();
        UUID fileNodeId = UUID.randomUUID();
        UUID coverFileId = UUID.randomUUID();
        List<UUID> firstPage = new ArrayList<>();
        for (int index = 0; index < 500; index++) {
            firstPage.add(UUID.randomUUID());
        }
        UUID cursor = firstPage.get(firstPage.size() - 1);
        PageRequest page = PageRequest.of(0, 500);
        PhotoItem photo = new PhotoItem();
        photo.setId(photoId);
        photo.setOwnerUserId(OWNER_ID);
        photo.setFileNodeId(fileNodeId);
        FileDescriptor file = new FileDescriptor(
                fileNodeId, OWNER_ID, null, "FILE", "a.jpg", "/a.jpg", "image/jpeg", 10L,
                null, null, false, false, SpaceType.PERSONAL, OWNER_ID, Instant.now(), Instant.now());
        PhotoSourceFileService.StagedPhotoFile staged = mock(PhotoSourceFileService.StagedPhotoFile.class);
        when(staged.fileName()).thenReturn("a.jpg");
        when(staged.raw()).thenReturn(false);
        when(taskRecordService.claimForExecution(taskId, "PROCESSING")).thenReturn(true);
        when(photoItemRepository.countMissingCover(OWNER_ID)).thenReturn(501L);
        when(photoItemRepository.findIdsMissingCoverAfter(OWNER_ID, new UUID(0L, 0L), page))
                .thenReturn(firstPage);
        when(photoItemRepository.findIdsMissingCoverAfter(OWNER_ID, cursor, page))
                .thenReturn(List.of(photoId));
        when(photoItemRepository.findAllById(any())).thenAnswer(invocation -> {
            Collection<UUID> ids = invocation.getArgument(0);
            return ids.contains(photoId) ? List.of(photo) : List.of();
        });
        when(fileMetadataQueryService.findAllByIds(any())).thenAnswer(invocation -> {
            Collection<UUID> ids = invocation.getArgument(0);
            return ids.contains(fileNodeId) ? List.of(file) : List.of();
        });
        when(sourceFileService.stageReadable(OWNER_ID, fileNodeId)).thenReturn(staged);
        when(fileDetector.isDecodable("a.jpg")).thenReturn(true);
        when(thumbnailService.generateAndStoreFile(eq(OWNER_ID), eq(fileNodeId), any(), eq("a.jpg")))
                .thenReturn(coverFileId);
        when(photoItemRepository.save(photo)).thenReturn(photo);

        service.executeThumbnailRegeneration(taskId, OWNER_ID);

        // 失败照片会留在"缺失"集合里，只能用 ID 游标推进；重查同一条件会反复取到同一批。
        InOrder cursorOrder = inOrder(photoItemRepository);
        cursorOrder.verify(photoItemRepository).findIdsMissingCoverAfter(OWNER_ID, new UUID(0L, 0L), page);
        cursorOrder.verify(photoItemRepository).findIdsMissingCoverAfter(OWNER_ID, cursor, page);
        assertThat(photo.getCoverFileId()).isEqualTo(coverFileId);
        verify(photoItemRepository).save(photo);
        verify(taskRecordService).markCompleted(taskId, Map.of("regenerated", 1));
    }

    @Test
    void thumbnailRegenerationMarksTaskFailedAndRethrowsWhenTheScanFails() {
        UUID taskId = UUID.randomUUID();
        when(taskRecordService.claimForExecution(taskId, "PROCESSING")).thenReturn(true);
        when(photoItemRepository.countMissingCover(OWNER_ID)).thenReturn(1L);
        when(photoItemRepository.findIdsMissingCoverAfter(any(), any(), any()))
                .thenThrow(new IllegalStateException("db down"));

        assertThatThrownBy(() -> service.executeThumbnailRegeneration(taskId, OWNER_ID))
                .isInstanceOf(IllegalStateException.class)
                .hasMessage("db down");

        verify(taskRecordService).markFailed(eq(taskId), eq("db down"), any());
        verify(taskRecordService, never()).markCompleted(eq(taskId), anyMap());
    }

    private FileDescriptor descriptor(String name) {
        return new FileDescriptor(
                UUID.randomUUID(),
                OWNER_ID,
                null,
                "FILE",
                name,
                "/" + name,
                "image/jpeg",
                1024L,
                null,
                null,
                false,
                false,
                SpaceType.PERSONAL,
                OWNER_ID,
                Instant.now(),
                Instant.now()
        );
    }

    private PhotoScanJob queuedJob() {
        PhotoScanJob job = new PhotoScanJob();
        job.setId(JOB_ID);
        job.setTaskId(JOB_ID);
        job.setOwnerUserId(OWNER_ID);
        job.setStatus(TaskStatus.QUEUED.getValue());
        return job;
    }
}
