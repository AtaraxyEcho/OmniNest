package com.omninest.modules.photos.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
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
import com.omninest.modules.file.service.FileMetadataQueryService;
import com.omninest.modules.file.service.FilePostProcessingTaskService;
import com.omninest.modules.file.service.FileQueryService;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.notification.port.NotificationPublisher;
import com.omninest.modules.photos.domain.PhotoScanJob;
import com.omninest.modules.photos.repository.PhotoItemRepository;
import com.omninest.modules.photos.repository.PhotoScanJobRepository;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import com.omninest.modules.task.domain.TaskStatus;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.InOrder;
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
            filePostProcessingTaskService,
            syncEventService,
            readThroughCache,
            transactionManager
    );

    @BeforeEach
    void setUp() {
        service.initTransactionTemplate();
        when(taskRecordService.claimForExecution(JOB_ID, "SCANNING")).thenReturn(true);
        when(fileMetadataQueryService.listOwnedImages(OWNER_ID)).thenReturn(List.of());
        when(scanJobRepository.save(any(PhotoScanJob.class))).thenAnswer(invocation -> {
            PhotoScanJob saved = invocation.getArgument(0);
            // 模拟 Hibernate merge：每次保存后 version 前进，返回实例携带新版本号。
            saved.setVersion(saved.getVersion() + 1);
            return saved;
        });
        when(transactionManager.getTransaction(any())).thenReturn(mock(TransactionStatus.class));
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
        when(fileMetadataQueryService.listOwnedImages(OWNER_ID))
                .thenThrow(new IllegalStateException("元数据查询不可用"));

        service.executeScanJob(JOB_ID, OWNER_ID);

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

    private PhotoScanJob queuedJob() {
        PhotoScanJob job = new PhotoScanJob();
        job.setId(JOB_ID);
        job.setTaskId(JOB_ID);
        job.setOwnerUserId(OWNER_ID);
        job.setStatus(TaskStatus.QUEUED.getValue());
        return job;
    }
}
