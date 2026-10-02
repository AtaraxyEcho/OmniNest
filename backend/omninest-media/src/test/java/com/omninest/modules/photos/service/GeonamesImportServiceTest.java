package com.omninest.modules.photos.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.error.BusinessException;
import com.omninest.common.messaging.DomainEventPublisher;
import com.omninest.common.messaging.QueueNames;
import com.omninest.common.config.ConfigRefreshEvent;
import com.omninest.modules.photos.config.GeonamesImportProperties;
import com.omninest.modules.photos.domain.GeoDataset;
import com.omninest.modules.photos.repository.GeoCityRepository;
import com.omninest.modules.photos.repository.GeoDatasetRepository;
import com.omninest.modules.task.service.TaskRecordService;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.mockito.ArgumentCaptor;
import org.mockito.Mockito;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.SimpleTransactionStatus;
import org.springframework.transaction.support.TransactionTemplate;

/** GeoNames 导入执行服务测试：阶段推进、幂等 upsert、阶段恢复、发布与广播。 */
class GeonamesImportServiceTest {

    private static final String CITIES_FILE = String.join("\n",
            "1809858\tGuangzhou\tGuangzhou\tGZ\t23.11667\t113.25\tP\tPPTA\tCN\t\t30\t\t\t\t15200000\t11\t21\tAsia/Shanghai",
            "1816663\tHangzhou\tHangzhou\tHZ\t30.29365\t120.16143\tP\tPPTA\tCN\t\t02\t\t\t\t11900000\t19\t41\tAsia/Shanghai",
            "");

    private static final String ADMIN1_FILE = String.join("\n",
            "CN.30\tGuangdong Sheng\tGuangdong\t1808702",
            "CN.02\tZhejiang Sheng\tZhejiang\t1784658",
            "");

    private static final String COUNTRY_FILE = String.join("\n",
            "#ISO\tISO3\tISO-Numeric\tfips\tCountry\tCapital",
            "CN\tCHN\t156\tCH\tChina\tBeijing\t0\t\t\t\t\t\t\t\t\t\t1814991",
            "");

    private static final String ALTERNATES_FILE = String.join("\n",
            "10001\t1809858\tzh-Hans\t广州市\t1\t0\t0\t0",
            "10002\t1809858\tzh-Hant\t廣州市\t0\t0\t0\t0",
            "10003\t1808702\tzh-Hans\t广东省\t0\t0\t0\t0",
            "10004\t1814991\tzh-Hans\t中国\t1\t0\t0\t0",
            "10005\t9999999\tzh-Hans\t不在范围\t1\t0\t0\t0",
            "");

    @TempDir
    Path tempDir;

    private GeoDatasetRepository datasetRepository;
    private GeoCityRepository cityRepository;
    private TaskRecordService taskRecordService;
    private GeoCityIndex geoCityIndex;
    private DomainEventPublisher eventPublisher;
    private GeoDataset dataset;
    private GeonamesImportService service;

    @BeforeEach
    void setUp() throws IOException {
        datasetRepository = Mockito.mock(GeoDatasetRepository.class);
        cityRepository = Mockito.mock(GeoCityRepository.class);
        taskRecordService = Mockito.mock(TaskRecordService.class);
        geoCityIndex = Mockito.mock(GeoCityIndex.class);
        eventPublisher = Mockito.mock(DomainEventPublisher.class);

        dataset = new GeoDataset();
        dataset.setId(UUID.randomUUID());
        dataset.setDatasetVersion("2026-09-05-cities5000-001");
        dataset.setStatus(GeoDataset.STATUS_IMPORTING);

        when(taskRecordService.taskPayload(any())).thenReturn(Map.of(
                "datasetId", dataset.getId().toString(),
                "datasetVersion", dataset.getDatasetVersion(),
                "dumpDate", "2026-09-05"));
        when(taskRecordService.taskPhase(any())).thenReturn(null);
        when(taskRecordService.claimForExecution(any(), anyString())).thenReturn(true);
        when(taskRecordService.isCancelled(any())).thenReturn(false);
        when(taskRecordService.taskResult(any())).thenReturn(Map.of());
        when(datasetRepository.findById(dataset.getId())).thenReturn(Optional.of(dataset));
        when(cityRepository.countByDatasetId(dataset.getId())).thenReturn(2L);
        when(cityRepository.findGeonameIdsByDatasetId(dataset.getId()))
                .thenReturn(List.of(1809858L, 1816663L));

        PhotosRuntimeConfigService configService = Mockito.mock(PhotosRuntimeConfigService.class);
        when(configService.geoImportBatchSize()).thenReturn(2);

        PlatformTransactionManager transactionManager = mock(PlatformTransactionManager.class);
        when(transactionManager.getTransaction(any())).thenReturn(new SimpleTransactionStatus());

        service = new GeonamesImportService(
                datasetRepository,
                cityRepository,
                new GeoNamesParser(),
                propertiesFor(tempDir),
                configService,
                taskRecordService,
                new TransactionTemplate(transactionManager),
                geoCityIndex,
                eventPublisher);

        write("cities5000.txt", CITIES_FILE);
        write("admin1CodesASCII.txt", ADMIN1_FILE);
        write("countryInfo.txt", COUNTRY_FILE);
        write("alternateNamesV2.txt", ALTERNATES_FILE);
    }

    private GeonamesImportProperties propertiesFor(Path dir) {
        GeonamesImportProperties properties = new GeonamesImportProperties();
        properties.setDir(dir.toString());
        return properties;
    }

    private void write(String fileName, String content) throws IOException {
        // 方案 B：四个 dump 文件直接平铺在共享目录下。
        Files.createDirectories(tempDir);
        Files.writeString(tempDir.resolve(fileName), content, StandardCharsets.UTF_8);
    }

    @Test
    void fullRunUpsertsCitiesFillsZhPublishesAndBroadcasts() {
        service.executeImportTask(UUID.randomUUID());

        verify(cityRepository, Mockito.times(1)).upsertCity(
                eq(dataset.getId()), eq(1809858L), eq("Guangzhou"), isNull(), eq("CN"),
                eq("China"), isNull(), eq("Guangdong"), isNull(), any(), any(), eq(15200000L), eq("PPTA"));
        verify(cityRepository, Mockito.times(1)).upsertCity(
                eq(dataset.getId()), eq(1816663L), eq("Hangzhou"), isNull(), eq("CN"),
                eq("China"), isNull(), eq("Zhejiang"), isNull(), any(), any(), eq(11900000L), eq("PPTA"));

        verify(cityRepository).updateCityNameZh(dataset.getId(), 1809858L, "广州市");
        verify(cityRepository).updateProvinceNameZh(dataset.getId(), "Guangdong", "广东省");
        verify(cityRepository).updateCountryNameZh(dataset.getId(), "CN", "中国");
        // 范围外的候选不回填。
        verify(cityRepository, never()).updateCityNameZh(eq(dataset.getId()), eq(9999999L), anyString());

        assertEquals(GeoDataset.STATUS_PUBLISHED, dataset.getStatus());
        ArgumentCaptor<Map<String, Object>> resultCaptor = ArgumentCaptor.captor();
        verify(taskRecordService).markCompleted(any(), resultCaptor.capture());
        assertEquals("2026-09-05-cities5000-001", resultCaptor.getValue().get("datasetVersion"));
        assertEquals(2L, resultCaptor.getValue().get("cities"));

        verify(geoCityIndex).reloadCurrentPublished();
        ArgumentCaptor<Object> broadcastCaptor = ArgumentCaptor.forClass(Object.class);
        verify(eventPublisher).publishFanout(eq(QueueNames.CONFIG_REFRESH_EXCHANGE), broadcastCaptor.capture());
        ConfigRefreshEvent broadcast = (ConfigRefreshEvent) broadcastCaptor.getValue();
        assertEquals(
                GeoDatasetService.BROADCAST_KEY_PREFIX + "2026-09-05-cities5000-001",
                broadcast.key());
    }

    @Test
    void phaseRecoverySkipsCompletedPhases() {
        when(taskRecordService.taskPhase(any())).thenReturn(
                GeonamesImportService.PHASE_IMPORTING_ALTERNATE_NAMES);

        service.executeImportTask(UUID.randomUUID());

        verify(cityRepository, never()).upsertCity(any(), anyLong(), anyString(), any(), anyString(),
                any(), any(), any(), any(), any(), any(), anyLong(), any());
        verify(cityRepository).updateCityNameZh(dataset.getId(), 1809858L, "广州市");
        assertEquals(GeoDataset.STATUS_PUBLISHED, dataset.getStatus());
    }

    @Test
    void failureMarksDatasetFailedAndPropagates() throws IOException {
        Files.delete(tempDir.resolve("cities5000.txt"));

        assertThrows(BusinessException.class, () -> service.executeImportTask(UUID.randomUUID()));

        assertEquals(GeoDataset.STATUS_FAILED, dataset.getStatus());
        verify(taskRecordService, never()).markCompleted(any(), any());
        verify(eventPublisher, never()).publishFanout(any(), any());
    }

    @Test
    void publishIsIdempotentWhenAlreadyPublished() {
        dataset.setStatus(GeoDataset.STATUS_PUBLISHED);
        when(taskRecordService.taskPhase(any())).thenReturn(GeonamesImportService.PHASE_PUBLISHING);

        service.executeImportTask(UUID.randomUUID());

        verify(datasetRepository, never()).findFirstByStatusForUpdate(GeoDataset.STATUS_PUBLISHED);
        verify(taskRecordService).markCompleted(any(), any());
    }

    @Test
    void emptyDatasetFailsValidation() {
        when(cityRepository.countByDatasetId(dataset.getId())).thenReturn(0L);

        assertThrows(BusinessException.class, () -> service.executeImportTask(UUID.randomUUID()));

        assertEquals(GeoDataset.STATUS_FAILED, dataset.getStatus());
        assertTrue(dataset.getStatus().equals(GeoDataset.STATUS_FAILED));
    }
}
