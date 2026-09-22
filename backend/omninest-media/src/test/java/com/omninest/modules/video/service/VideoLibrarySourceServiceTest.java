package com.omninest.modules.video.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyMap;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.messaging.QueueNames;
import com.omninest.common.error.BusinessException;
import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncScope;
import com.omninest.modules.file.domain.StorageLocation;
import com.omninest.modules.file.service.StorageLocationService;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import com.omninest.modules.video.domain.VideoLibrarySource;
import com.omninest.modules.video.domain.MediaImportPolicy;
import com.omninest.modules.video.domain.MediaLibraryType;
import com.omninest.modules.video.domain.MediaScanRun;
import com.omninest.modules.video.dto.MovieDtos.ScrapeTaskDto;
import com.omninest.modules.video.dto.VideoLibrarySourceDtos.CreateVideoLibrarySourceRequest;
import com.omninest.modules.video.event.LocalVideoLibraryScanRequestedEvent;
import com.omninest.modules.video.repository.VideoLibrarySourceRepository;
import com.omninest.modules.video.repository.MediaScanRunRepository;
import com.omninest.modules.video.repository.MediaScanBatchRepository;
import com.omninest.modules.video.repository.MediaScanCandidateRepository;
import com.omninest.modules.video.repository.MediaVideoItemRepository;
import java.util.Optional;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.Test;

/**
 * 影视库本地来源任务编排服务测试。
 *
 * @author OmniNest
 */
class VideoLibrarySourceServiceTest {
    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID SOURCE_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");
    private static final UUID LOCATION_ID = UUID.fromString("30000000-0000-0000-0000-000000000001");
    private static final UUID OTHER_LOCATION_ID = UUID.fromString("30000000-0000-0000-0000-000000000002");
    private static final UUID RUN_ID = UUID.fromString("40000000-0000-0000-0000-000000000001");

    private final VideoLibrarySourceRepository sourceRepository = mock(VideoLibrarySourceRepository.class);
    private final MediaScanRunRepository runRepository = mock(MediaScanRunRepository.class);
    private final MediaScanBatchRepository batchRepository = mock(MediaScanBatchRepository.class);
    private final MediaScanCandidateRepository candidateRepository = mock(MediaScanCandidateRepository.class);
    private final MediaVideoItemRepository videoItemRepository = mock(MediaVideoItemRepository.class);
    private final StorageLocationService storageLocationService = mock(StorageLocationService.class);
    private final TaskRecordService taskRecordService = mock(TaskRecordService.class);
    private final TaskDispatchService taskDispatchService = mock(TaskDispatchService.class);
    private final MediaLibraryDiscoveryExecutor discoveryExecutor = mock(MediaLibraryDiscoveryExecutor.class);
    private final MediaLibraryAccessService accessService = mock(MediaLibraryAccessService.class);
    private final MediaSyncEventService syncEventService = mock(MediaSyncEventService.class);
    private final VideoLibrarySourceService service = new VideoLibrarySourceService(
            sourceRepository,
            runRepository,
            batchRepository,
            candidateRepository,
            videoItemRepository,
            storageLocationService,
            taskRecordService,
            taskDispatchService,
            discoveryExecutor,
            accessService,
            syncEventService
    );

    @Test
    void deleteEmitsVideoLibraryEventForOperatorDevices() {
        VideoLibrarySource source = source("COMPLETED");
        when(accessService.requireManage(OWNER_ID, SOURCE_ID)).thenReturn(source);
        when(videoItemRepository.countByLibrarySourceId(SOURCE_ID)).thenReturn(0L);
        when(runRepository.findAllByLibrarySourceId(SOURCE_ID)).thenReturn(List.of());

        service.delete(OWNER_ID, SOURCE_ID);

        verify(sourceRepository).delete(source);
        verify(syncEventService).record(
                eq(OWNER_ID),
                eq(SyncScope.VIDEO),
                eq("VIDEO_LIBRARY"),
                eq(SOURCE_ID.toString()),
                eq(SyncAction.UPDATED),
                isNull(),
                anyMap()
        );
    }

    @Test
    void scanPersistsTaskAndOutboxWithoutScanningOnRequestThread() {
        VideoLibrarySource source = source("COMPLETED");
        when(accessService.requireManage(OWNER_ID, SOURCE_ID)).thenReturn(source);
        when(sourceRepository.save(source)).thenReturn(source);
        when(runRepository.existsByLibrarySourceIdAndStatusIn(eq(SOURCE_ID), any()))
                .thenReturn(false);
        when(runRepository.findFirstByLibrarySourceIdOrderByCreatedAtDesc(SOURCE_ID))
                .thenReturn(Optional.empty());
        when(runRepository.save(any(MediaScanRun.class))).thenAnswer(invocation -> {
            MediaScanRun run = invocation.getArgument(0);
            run.setId(RUN_ID);
            return run;
        });

        ScrapeTaskDto result = service.scan(OWNER_ID, SOURCE_ID);

        assertThat(result.status()).isEqualTo("QUEUED");
        assertThat(source.getScanStatus()).isEqualTo("QUEUED");
        verify(taskRecordService).createQueuedTask(
                eq(result.taskId()),
                eq(OWNER_ID),
                eq("LOCAL_VIDEO_LIBRARY_DISCOVERY"),
                eq(QueueNames.LOCAL_VIDEO_LIBRARY_SCAN_ROUTING_KEY),
                eq("QUEUED"),
                eq("MEDIA_SCAN_RUN"),
                eq(RUN_ID),
                any()
        );
        verify(taskDispatchService).enqueue(
                eq(result.taskId()),
                eq(QueueNames.TASK_EXCHANGE),
                eq(QueueNames.LOCAL_VIDEO_LIBRARY_SCAN_ROUTING_KEY),
                any(LocalVideoLibraryScanRequestedEvent.class)
        );
    }

    @Test
    void executeScanDelegatesToDiscoveryExecutor() {
        UUID taskId = UUID.fromString("50000000-0000-0000-0000-000000000001");
        LocalVideoLibraryScanRequestedEvent event = new LocalVideoLibraryScanRequestedEvent(
                taskId,
                OWNER_ID,
                SOURCE_ID,
                RUN_ID
        );

        service.executeScan(event);

        verify(discoveryExecutor).execute(event);
    }

    @Test
    void createRejectsCaseInsensitiveChildPathOverlap() {
        StorageLocation location = systemLocation(LOCATION_ID, "media", ".");
        VideoLibrarySource existing = source("READY");
        existing.setRelativeRoot("Movies");
        when(storageLocationService.requireAccessibleLocation(OWNER_ID, LOCATION_ID)).thenReturn(location);
        when(storageLocationService.listByMountKeyForBusiness("media")).thenReturn(List.of(location));
        when(sourceRepository.findByStorageLocationId(LOCATION_ID)).thenReturn(List.of(existing));

        CreateVideoLibrarySourceRequest request = new CreateVideoLibrarySourceRequest(
                "动作电影",
                null,
                LOCATION_ID,
                "movies/Action",
                MediaLibraryType.MOVIE,
                MediaImportPolicy.MANUAL_REVIEW,
                true
        );

        assertThatThrownBy(() -> service.create(OWNER_ID, request))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("重复或重叠");
    }

    @Test
    void createRejectsCrossLocationOverlapOnSameMount() {
        StorageLocation wizardLocation = systemLocation(LOCATION_ID, "media", "Movies");
        StorageLocation rootLocation = systemLocation(OTHER_LOCATION_ID, "media", ".");
        VideoLibrarySource existing = source("READY");
        existing.setStorageLocationId(LOCATION_ID);
        existing.setRelativeRoot(".");
        when(storageLocationService.requireAccessibleLocation(OWNER_ID, OTHER_LOCATION_ID))
                .thenReturn(rootLocation);
        when(storageLocationService.listByMountKeyForBusiness("media"))
                .thenReturn(List.of(wizardLocation, rootLocation));
        when(sourceRepository.findByStorageLocationId(LOCATION_ID)).thenReturn(List.of(existing));
        when(sourceRepository.findByStorageLocationId(OTHER_LOCATION_ID)).thenReturn(List.of());

        CreateVideoLibrarySourceRequest request = new CreateVideoLibrarySourceRequest(
                "直达电影",
                null,
                OTHER_LOCATION_ID,
                "Movies",
                MediaLibraryType.MOVIE,
                MediaImportPolicy.MANUAL_REVIEW,
                true
        );

        assertThatThrownBy(() -> service.create(OWNER_ID, request))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("重复或重叠");
    }

    @Test
    void createWithMountKeyRequiresSystemConfigManagePermission() {
        doThrow(new BusinessException(ErrorCode.FORBIDDEN, "当前用户没有所需权限"))
                .when(accessService).requireSystemConfigManage(OWNER_ID);

        CreateVideoLibrarySourceRequest request = new CreateVideoLibrarySourceRequest(
                "直达电影",
                "media",
                null,
                ".",
                MediaLibraryType.MOVIE,
                MediaImportPolicy.MANUAL_REVIEW,
                true
        );

        assertThatThrownBy(() -> service.create(OWNER_ID, request))
                .isInstanceOf(BusinessException.class);
        verify(storageLocationService, never()).findOrCreateSystemLocation(any(), any(), any());
    }

    @Test
    void createRejectsMissingOrDuplicateLocationSelector() {
        CreateVideoLibrarySourceRequest both = new CreateVideoLibrarySourceRequest(
                "直达电影", "media", LOCATION_ID, ".", MediaLibraryType.MOVIE,
                MediaImportPolicy.MANUAL_REVIEW, true);
        CreateVideoLibrarySourceRequest neither = new CreateVideoLibrarySourceRequest(
                "直达电影", null, null, ".", MediaLibraryType.MOVIE,
                MediaImportPolicy.MANUAL_REVIEW, true);

        assertThatThrownBy(() -> service.create(OWNER_ID, both))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("二选一");
        assertThatThrownBy(() -> service.create(OWNER_ID, neither))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("二选一");
    }

    @Test
    void createWithMountKeyDelegatesToFindOrCreateSystemLocation() {
        StorageLocation rootLocation = systemLocation(OTHER_LOCATION_ID, "media", ".");
        when(storageLocationService.findOrCreateSystemLocation(OWNER_ID, "media", "."))
                .thenReturn(new StorageLocationService.SystemLocationResolution(rootLocation, true));
        when(storageLocationService.requireAccessibleLocation(OWNER_ID, OTHER_LOCATION_ID))
                .thenReturn(rootLocation);
        when(storageLocationService.listByMountKeyForBusiness("media")).thenReturn(List.of(rootLocation));
        when(sourceRepository.findByStorageLocationId(OTHER_LOCATION_ID)).thenReturn(List.of());
        when(sourceRepository.save(any(VideoLibrarySource.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        CreateVideoLibrarySourceRequest request = new CreateVideoLibrarySourceRequest(
                "直达电影",
                "media",
                null,
                "Movies",
                MediaLibraryType.MOVIE,
                MediaImportPolicy.MANUAL_REVIEW,
                true
        );

        var result = service.create(OWNER_ID, request);

        assertThat(result.storageLocationId()).isEqualTo(OTHER_LOCATION_ID);
        assertThat(result.relativeRoot()).isEqualTo("Movies");
        verify(accessService).requireSystemConfigManage(OWNER_ID);
        verify(storageLocationService).findOrCreateSystemLocation(OWNER_ID, "media", ".");
        verify(storageLocationService, never()).rollbackAutoCreatedLocation(any());
    }

    @Test
    void createWithMountKeyRollsBackAutoCreatedLocationOnFailure() {
        StorageLocation rootLocation = systemLocation(OTHER_LOCATION_ID, "media", ".");
        when(storageLocationService.findOrCreateSystemLocation(OWNER_ID, "media", "."))
                .thenReturn(new StorageLocationService.SystemLocationResolution(rootLocation, true));
        when(storageLocationService.requireAccessibleLocation(OWNER_ID, OTHER_LOCATION_ID))
                .thenReturn(rootLocation);
        // 同挂载已有重叠库源，创建在冲突检查处失败。
        StorageLocation wizardLocation = systemLocation(LOCATION_ID, "media", "Movies");
        VideoLibrarySource existing = source("READY");
        existing.setStorageLocationId(LOCATION_ID);
        existing.setRelativeRoot(".");
        when(storageLocationService.listByMountKeyForBusiness("media"))
                .thenReturn(List.of(wizardLocation, rootLocation));
        when(sourceRepository.findByStorageLocationId(LOCATION_ID)).thenReturn(List.of(existing));
        when(sourceRepository.findByStorageLocationId(OTHER_LOCATION_ID)).thenReturn(List.of());

        CreateVideoLibrarySourceRequest request = new CreateVideoLibrarySourceRequest(
                "直达电影",
                "media",
                null,
                "Movies",
                MediaLibraryType.MOVIE,
                MediaImportPolicy.MANUAL_REVIEW,
                true
        );

        assertThatThrownBy(() -> service.create(OWNER_ID, request))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("重复或重叠");
        verify(storageLocationService).rollbackAutoCreatedLocation(OTHER_LOCATION_ID);
    }

    @Test
    void createWithMountKeyFailureKeepsReusedLocation() {
        StorageLocation rootLocation = systemLocation(OTHER_LOCATION_ID, "media", ".");
        // 命中既有位置（created=false），失败时不做回滚清理。
        when(storageLocationService.findOrCreateSystemLocation(OWNER_ID, "media", "."))
                .thenReturn(new StorageLocationService.SystemLocationResolution(rootLocation, false));
        when(storageLocationService.requireAccessibleLocation(OWNER_ID, OTHER_LOCATION_ID))
                .thenReturn(rootLocation);
        StorageLocation wizardLocation = systemLocation(LOCATION_ID, "media", "Movies");
        VideoLibrarySource existing = source("READY");
        existing.setStorageLocationId(LOCATION_ID);
        existing.setRelativeRoot(".");
        when(storageLocationService.listByMountKeyForBusiness("media"))
                .thenReturn(List.of(wizardLocation, rootLocation));
        when(sourceRepository.findByStorageLocationId(LOCATION_ID)).thenReturn(List.of(existing));
        when(sourceRepository.findByStorageLocationId(OTHER_LOCATION_ID)).thenReturn(List.of());

        CreateVideoLibrarySourceRequest request = new CreateVideoLibrarySourceRequest(
                "直达电影",
                "media",
                null,
                "Movies",
                MediaLibraryType.MOVIE,
                MediaImportPolicy.MANUAL_REVIEW,
                true
        );

        assertThatThrownBy(() -> service.create(OWNER_ID, request))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("重复或重叠");
        verify(storageLocationService, never()).rollbackAutoCreatedLocation(any());
    }

    private StorageLocation systemLocation(UUID locationId, String mountKey, String relativeRoot) {
        StorageLocation location = new StorageLocation();
        location.setId(locationId);
        location.setMountKey(mountKey);
        location.setRelativeRoot(relativeRoot);
        location.setScopeType("SYSTEM");
        location.setEnabled(true);
        return location;
    }

    private VideoLibrarySource source(String scanStatus) {
        VideoLibrarySource source = new VideoLibrarySource();
        source.setId(SOURCE_ID);
        source.setOwnerUserId(OWNER_ID);
        source.setStorageLocationId(LOCATION_ID);
        source.setName("本地影片");
        source.setRelativeRoot("movies");
        source.setLibraryType(MediaLibraryType.MOVIE.name());
        source.setEnabled(true);
        source.setScanStatus(scanStatus);
        return source;
    }
}
