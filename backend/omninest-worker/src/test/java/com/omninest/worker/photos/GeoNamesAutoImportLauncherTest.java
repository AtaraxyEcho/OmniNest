package com.omninest.worker.photos;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.concurrency.DistributedLock;
import com.omninest.modules.photos.config.GeonamesImportProperties;
import com.omninest.modules.photos.service.GeoDatasetService;
import com.omninest.modules.photos.service.PhotosRuntimeConfigService;
import com.omninest.modules.task.service.TaskRecordService;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.mockito.Mockito;

/** GeoNames 自动导入触发器测试：触发条件、并发锁与异常吞噬。 */
class GeoNamesAutoImportLauncherTest {

    @TempDir
    Path tempDir;

    private GeoDatasetService geoDatasetService;
    private TaskRecordService taskRecordService;
    private PhotosRuntimeConfigService configService;
    private DistributedLock distributedLock;
    private GeoNamesAutoImportLauncher launcher;

    @BeforeEach
    void setUp() throws IOException {
        geoDatasetService = Mockito.mock(GeoDatasetService.class);
        taskRecordService = Mockito.mock(TaskRecordService.class);
        configService = Mockito.mock(PhotosRuntimeConfigService.class);
        distributedLock = Mockito.mock(DistributedLock.class);

        when(distributedLock.newToken()).thenReturn("token");
        when(distributedLock.tryLock(anyString(), anyString(), any())).thenReturn(true);
        when(configService.isGeoAutoImportEnabled()).thenReturn(true);
        when(geoDatasetService.currentPublishedVersion()).thenReturn(null);
        when(taskRecordService.findActiveTaskIdsByType(anyString(), any())).thenReturn(List.of());
        when(geoDatasetService.importRootDir()).thenReturn(tempDir.toString());
        for (String file : List.of("cities5000.txt", "admin1CodesASCII.txt", "countryInfo.txt")) {
            Files.writeString(tempDir.resolve(file), "content");
        }
        when(geoDatasetService.createImportTask(any(), any())).thenReturn(
                new GeoDatasetService.GeoImportCreated(UUID.randomUUID(), UUID.randomUUID(), "v1"));

        launcher = new GeoNamesAutoImportLauncher(
                geoDatasetService,
                taskRecordService,
                configService,
                distributedLock);
    }

    @Test
    void triggersImportWhenNoPublishedDatasetAndFilesPresent() {
        launcher.autoImportOnStartup();

        verify(geoDatasetService).createImportTask(any(), eq(new UUID(0L, 0L)));
        verify(distributedLock).unlock(anyString(), eq("token"));
    }

    @Test
    void skipsWhenPublishedDatasetExists() {
        when(geoDatasetService.currentPublishedVersion()).thenReturn("2026-11-01-geonames-001");

        launcher.autoImportOnStartup();

        verify(geoDatasetService, never()).createImportTask(any(), any());
    }

    @Test
    void skipsWhenActiveImportTaskExists() {
        when(taskRecordService.findActiveTaskIdsByType(anyString(), any()))
                .thenReturn(List.of(UUID.randomUUID()));

        launcher.autoImportOnStartup();

        verify(geoDatasetService, never()).createImportTask(any(), any());
    }

    @Test
    void skipsWhenRequiredFileMissing() throws IOException {
        Files.delete(tempDir.resolve("countryInfo.txt"));

        launcher.autoImportOnStartup();

        verify(geoDatasetService, never()).createImportTask(any(), any());
    }

    @Test
    void skipsWhenConfigDisabled() {
        when(configService.isGeoAutoImportEnabled()).thenReturn(false);

        launcher.autoImportOnStartup();

        verify(geoDatasetService, never()).createImportTask(any(), any());
    }

    @Test
    void skipsWhenLockNotAcquired() {
        when(distributedLock.tryLock(anyString(), anyString(), any())).thenReturn(false);

        launcher.autoImportOnStartup();

        verify(geoDatasetService, never()).createImportTask(any(), any());
        verify(distributedLock, never()).unlock(anyString(), anyString());
    }

    @Test
    void creationFailureDoesNotPropagate() {
        when(geoDatasetService.createImportTask(any(), any()))
                .thenThrow(new IllegalStateException("boom"));

        assertDoesNotThrow(() -> launcher.autoImportOnStartup());
        verify(distributedLock).unlock(anyString(), eq("token"));
    }
}
