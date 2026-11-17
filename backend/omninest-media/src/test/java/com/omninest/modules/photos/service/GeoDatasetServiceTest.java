package com.omninest.modules.photos.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.photos.config.GeonamesImportProperties;
import com.omninest.modules.photos.domain.GeoDataset;
import com.omninest.modules.photos.event.PhotoGeoBackfillEvent;
import com.omninest.modules.photos.event.PhotoGeoImportEvent;
import com.omninest.modules.photos.repository.GeoDatasetRepository;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.Mockito;

/**
 * GeoNames 数据集任务创建测试：验证导入与回填任务经 Outbox 投递与活跃去重。
 *
 * @author OmniNest
 */
class GeoDatasetServiceTest {

    private static final UUID OPERATOR_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");

    private final GeoDatasetRepository geoDatasetRepository = mock(GeoDatasetRepository.class);
    private final GeoCityIndex geoCityIndex = mock(GeoCityIndex.class);
    private final TaskRecordService taskRecordService = mock(TaskRecordService.class);
    private final TaskDispatchService taskDispatchService = mock(TaskDispatchService.class);
    private final GeonamesImportProperties importProperties = mock(GeonamesImportProperties.class);
    private final GeoDatasetService service = new GeoDatasetService(
            geoDatasetRepository,
            geoCityIndex,
            taskRecordService,
            taskDispatchService,
            importProperties
    );

    @Test
    void createImportTaskEnqueuesThroughOutbox() {
        when(geoDatasetRepository.countByDatasetVersionStartingWith(anyString())).thenReturn(0L);
        when(geoDatasetRepository.findByDatasetVersion(anyString())).thenReturn(Optional.empty());
        when(geoDatasetRepository.save(any())).thenAnswer(invocation -> {
            // 实体主键由 JPA @PrePersist 生成，mock 仓储需自行补齐。
            GeoDataset dataset = invocation.getArgument(0);
            if (dataset.getId() == null) {
                dataset.setId(UUID.randomUUID());
            }
            return dataset;
        });

        var result = service.createImportTask(
                new GeoDatasetService.GeoImportRequest("2026-09-09", "hash-1"), OPERATOR_ID);

        ArgumentCaptor<PhotoGeoImportEvent> eventCaptor =
                ArgumentCaptor.forClass(PhotoGeoImportEvent.class);
        verify(taskDispatchService).enqueue(
                eq(result.taskId()),
                eq(QueueNames.TASK_EXCHANGE),
                eq(QueueNames.PHOTO_GEO_IMPORT_ROUTING_KEY),
                eventCaptor.capture()
        );
        assertThat(eventCaptor.getValue().datasetId()).isEqualTo(result.datasetId());
        assertThat(eventCaptor.getValue().datasetVersion()).isEqualTo(result.datasetVersion());
        assertThat(eventCaptor.getValue().dumpDate()).isEqualTo("2026-09-09");
    }

    @Test
    void createBackfillTaskEnqueuesThroughOutboxWithDefaults() {
        when(taskRecordService.findActiveTaskIdsByType(eq("PHOTO_GEO_BACKFILL"), any()))
                .thenReturn(List.of());
        when(geoDatasetRepository.findFirstByStatusOrderByPublishedAtDesc(any()))
                .thenReturn(Optional.empty());

        var result = service.createBackfillTask(OPERATOR_ID, null);

        ArgumentCaptor<PhotoGeoBackfillEvent> eventCaptor =
                ArgumentCaptor.forClass(PhotoGeoBackfillEvent.class);
        verify(taskDispatchService).enqueue(
                eq(result.taskId()),
                eq(QueueNames.TASK_EXCHANGE),
                eq(QueueNames.PHOTO_GEO_BACKFILL_ROUTING_KEY),
                eventCaptor.capture()
        );
        assertThat(eventCaptor.getValue().batchSize()).isPositive();
        assertThat(eventCaptor.getValue().datasetVersion()).isNull();
        assertThat(result.reused()).isFalse();
    }

    @Test
    void createBackfillTaskReusesActiveTaskWithoutDispatch() {
        UUID activeTaskId = UUID.randomUUID();
        when(taskRecordService.findActiveTaskIdsByType(eq("PHOTO_GEO_BACKFILL"), any()))
                .thenReturn(List.of(activeTaskId));

        var result = service.createBackfillTask(OPERATOR_ID, 100);

        assertThat(result.taskId()).isEqualTo(activeTaskId);
        assertThat(result.reused()).isTrue();
        Mockito.verifyNoInteractions(taskDispatchService);
    }
}
