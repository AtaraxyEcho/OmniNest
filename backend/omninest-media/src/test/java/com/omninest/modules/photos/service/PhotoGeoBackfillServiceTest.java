package com.omninest.modules.photos.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.concurrency.DistributedLock;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.photos.repository.PhotoItemRepository;
import com.omninest.modules.task.service.TaskRecordService;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.Mockito;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.SimpleTransactionStatus;
import org.springframework.transaction.support.TransactionTemplate;

/** 照片位置回填执行服务测试：keyset 游标推进、不覆盖已有地点、并发与取消。 */
class PhotoGeoBackfillServiceTest {

    private PhotoItemRepository photoItemRepository;
    private PhotoGeoService photoGeoService;
    private TaskRecordService taskRecordService;
    private GeoCityIndex geoCityIndex;
    private DistributedLock distributedLock;
    private PhotoGeoBackfillService service;

    private static final Instant CREATED_AT = Instant.parse("2026-09-05T00:00:00Z");

    @BeforeEach
    void setUp() {
        photoItemRepository = Mockito.mock(PhotoItemRepository.class);
        photoGeoService = Mockito.mock(PhotoGeoService.class);
        taskRecordService = Mockito.mock(TaskRecordService.class);
        geoCityIndex = Mockito.mock(GeoCityIndex.class);
        distributedLock = Mockito.mock(DistributedLock.class);

        when(distributedLock.newToken()).thenReturn("token");
        when(distributedLock.tryLock(anyString(), anyString(), any())).thenReturn(true);
        when(taskRecordService.taskPayload(any())).thenReturn(Map.of("batchSize", 2));
        when(taskRecordService.claimForExecution(any(), anyString())).thenReturn(true);
        when(taskRecordService.taskResult(any())).thenReturn(Map.of());
        when(taskRecordService.isCancelled(any())).thenReturn(false);
        when(photoItemRepository.countGeocodeBackfillRows()).thenReturn(3L);
        when(geoCityIndex.snapshotOfVersion(isNull())).thenReturn(GeoCitySnapshot.EMPTY);

        PlatformTransactionManager transactionManager = mock(PlatformTransactionManager.class);
        when(transactionManager.getTransaction(any())).thenReturn(new SimpleTransactionStatus());

        service = new PhotoGeoBackfillService(
                photoItemRepository,
                photoGeoService,
                taskRecordService,
                geoCityIndex,
                distributedLock,
                new TransactionTemplate(transactionManager));
    }

    private static PhotoItemRepository.GeocodeBackfillRow row(UUID id) {
        return new PhotoItemRepository.GeocodeBackfillRow() {
            @Override
            public UUID getId() {
                return id;
            }

            @Override
            public BigDecimal getGpsLatitude() {
                return BigDecimal.valueOf(23.13);
            }

            @Override
            public BigDecimal getGpsLongitude() {
                return BigDecimal.valueOf(113.26);
            }

            @Override
            public Instant getCreatedAt() {
                return CREATED_AT;
            }
        };
    }

    @Test
    void batchesAdvanceKeysetCursorAndComplete() {
        UUID firstId = UUID.randomUUID();
        UUID secondId = UUID.randomUUID();
        UUID thirdId = UUID.randomUUID();
        when(photoItemRepository.findGeocodeBackfillBatch(isNull(), isNull(), eq(2)))
                .thenReturn(List.of(row(firstId), row(secondId)));
        when(photoItemRepository.findGeocodeBackfillBatch(eq(CREATED_AT), eq(secondId), eq(2)))
                .thenReturn(List.of(row(thirdId)));
        when(photoItemRepository.findGeocodeBackfillBatch(eq(CREATED_AT), eq(thirdId), eq(2)))
                .thenReturn(List.of());
        Map<String, Object> geoInfo = Map.of("city", "Guangzhou", "cityZh", "广州市");
        when(photoGeoService.reverseGeocode(any(), any(), any())).thenReturn(geoInfo);
        when(photoItemRepository.updateGeocodeLocationIfAbsent(any(), anyString(), any()))
                .thenReturn(1);

        service.executeBackfillTask(UUID.randomUUID());

        verify(photoItemRepository).updateGeocodeLocationIfAbsent(
                eq(firstId), anyString(), any());
        verify(photoItemRepository).updateGeocodeLocationIfAbsent(
                eq(thirdId), anyString(), any());
        ArgumentCaptor<Map<String, Object>> resultCaptor = ArgumentCaptor.captor();
        verify(taskRecordService, Mockito.atLeastOnce()).updateResult(any(), resultCaptor.capture());
        Map<String, Object> lastResult = resultCaptor.getValue();
        assertEquals(CREATED_AT.toString(),
                ((Map<?, ?>) lastResult.get("cursor")).get("createdAt"));
        assertEquals(thirdId.toString(),
                ((Map<?, ?>) lastResult.get("cursor")).get("id"));
        ArgumentCaptor<Map<String, Object>> completedCaptor = ArgumentCaptor.captor();
        verify(taskRecordService).markCompleted(any(), completedCaptor.capture());
        assertEquals(3L, completedCaptor.getValue().get("updated"));
        assertEquals(0L, completedCaptor.getValue().get("skippedDistance"));
        verify(distributedLock).unlock(anyString(), eq("token"));
    }

    @Test
    void rowsWithoutMatchOnlyAdvanceCursor() {
        UUID firstId = UUID.randomUUID();
        UUID secondId = UUID.randomUUID();
        when(photoItemRepository.findGeocodeBackfillBatch(isNull(), isNull(), eq(2)))
                .thenReturn(List.of(row(firstId), row(secondId)));
        when(photoItemRepository.findGeocodeBackfillBatch(eq(CREATED_AT), eq(secondId), eq(2)))
                .thenReturn(List.of());
        when(photoGeoService.reverseGeocode(any(), any(), any())).thenReturn(Map.of());

        service.executeBackfillTask(UUID.randomUUID());

        verify(photoItemRepository, never())
                .updateGeocodeLocationIfAbsent(any(), anyString(), any());
        ArgumentCaptor<Map<String, Object>> completedCaptor = ArgumentCaptor.captor();
        verify(taskRecordService).markCompleted(any(), completedCaptor.capture());
        assertEquals(0L, completedCaptor.getValue().get("updated"));
        assertEquals(2L, completedCaptor.getValue().get("skippedDistance"));
    }

    @Test
    void conditionalUpdateMissCountedAsSkippedExisting() {
        UUID firstId = UUID.randomUUID();
        when(photoItemRepository.findGeocodeBackfillBatch(isNull(), isNull(), eq(2)))
                .thenReturn(List.of(row(firstId)));
        when(photoItemRepository.findGeocodeBackfillBatch(eq(CREATED_AT), eq(firstId), eq(2)))
                .thenReturn(List.of());
        when(photoGeoService.reverseGeocode(any(), any(), any()))
                .thenReturn(Map.of("city", "Guangzhou"));
        // 查询与写入之间照片已被其他写入填充：条件更新命中 0 行。
        when(photoItemRepository.updateGeocodeLocationIfAbsent(any(), anyString(), any()))
                .thenReturn(0);

        service.executeBackfillTask(UUID.randomUUID());

        ArgumentCaptor<Map<String, Object>> completedCaptor = ArgumentCaptor.captor();
        verify(taskRecordService).markCompleted(any(), completedCaptor.capture());
        assertEquals(0L, completedCaptor.getValue().get("updated"));
        assertEquals(1L, completedCaptor.getValue().get("skippedExisting"));
    }

    @Test
    void lockConflictSkipsExecutionAndThrowsRetryableError() {
        when(distributedLock.tryLock(anyString(), anyString(), any())).thenReturn(false);

        assertThrows(BusinessException.class, () -> service.executeBackfillTask(UUID.randomUUID()));

        verify(taskRecordService, never()).claimForExecution(any(), anyString());
        verify(distributedLock, never()).unlock(anyString(), anyString());
    }

    @Test
    void cancelledTaskIsMarkedCancelledWithoutUpdates() {
        when(taskRecordService.isCancelled(any())).thenReturn(true);

        service.executeBackfillTask(UUID.randomUUID());

        verify(taskRecordService).markCancelled(any());
        verify(photoItemRepository, never())
                .updateGeocodeLocationIfAbsent(any(), anyString(), any());
        verify(taskRecordService, never()).markCompleted(any(), any());
    }

    @Test
    void geocodeFailurePerRowDoesNotAbortBatch() {
        UUID firstId = UUID.randomUUID();
        UUID secondId = UUID.randomUUID();
        when(photoItemRepository.findGeocodeBackfillBatch(isNull(), isNull(), eq(2)))
                .thenReturn(List.of(row(firstId), row(secondId)));
        when(photoItemRepository.findGeocodeBackfillBatch(eq(CREATED_AT), eq(secondId), eq(2)))
                .thenReturn(List.of());
        when(photoGeoService.reverseGeocode(any(), any(), any()))
                .thenThrow(new RuntimeException("boom"))
                .thenReturn(Map.of("city", "Guangzhou"));
        when(photoItemRepository.updateGeocodeLocationIfAbsent(any(), anyString(), any()))
                .thenReturn(1);

        service.executeBackfillTask(UUID.randomUUID());

        ArgumentCaptor<Map<String, Object>> completedCaptor = ArgumentCaptor.captor();
        verify(taskRecordService).markCompleted(any(), completedCaptor.capture());
        assertEquals(1L, completedCaptor.getValue().get("failed"));
        assertEquals(1L, completedCaptor.getValue().get("updated"));
        assertTrue(completedCaptor.getValue().containsKey("skippedExisting"));
    }
}
