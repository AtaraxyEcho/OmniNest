package com.omninest.modules.photos.service;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.modules.file.service.DerivedAssetStorageService;
import com.omninest.modules.photos.config.PhotoBatchRetentionProperties;
import com.omninest.modules.photos.domain.PhotoBatchTask;
import com.omninest.modules.photos.repository.PhotoBatchTaskRepository;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.data.domain.Pageable;

/**
 * 照片批量任务过期清理测试。
 */
class PhotoBatchRetentionServiceTest {

    private final PhotoBatchTaskRepository taskRepository = mock(PhotoBatchTaskRepository.class);
    private final DerivedAssetStorageService derivedAssetStorageService =
            mock(DerivedAssetStorageService.class);
    private final PhotoBatchRetentionProperties properties = new PhotoBatchRetentionProperties();
    private final PhotoBatchRetentionService service = new PhotoBatchRetentionService(
            taskRepository, derivedAssetStorageService, properties);

    @Test
    void cleanupDeletesArchiveThenTaskRow() {
        UUID resultFileId = UUID.randomUUID();
        PhotoBatchTask task = task(resultFileId.toString());
        when(taskRepository.findTerminalBefore(eq(Set.of("COMPLETED", "FAILED")), any(Instant.class), any(Pageable.class)))
                .thenReturn(List.of(task));
        when(derivedAssetStorageService.deleteDerivedFileNode(resultFileId)).thenReturn(true);

        service.cleanupExpired();

        verify(derivedAssetStorageService).deleteDerivedFileNode(resultFileId);
        verify(taskRepository).delete(task);
    }

    @Test
    void cleanupKeepsTaskRowWhenArchiveDeletionFails() {
        UUID resultFileId = UUID.randomUUID();
        PhotoBatchTask task = task(resultFileId.toString());
        when(taskRepository.findTerminalBefore(eq(Set.of("COMPLETED", "FAILED")), any(Instant.class), any(Pageable.class)))
                .thenReturn(List.of(task));
        when(derivedAssetStorageService.deleteDerivedFileNode(resultFileId))
                .thenThrow(new IllegalStateException("object storage unavailable"));

        service.cleanupExpired();

        verify(taskRepository, never()).delete(task);
    }

    @Test
    void cleanupDeletesRowsWithoutResultFile() {
        PhotoBatchTask task = task(null);
        when(taskRepository.findTerminalBefore(eq(Set.of("COMPLETED", "FAILED")), any(Instant.class), any(Pageable.class)))
                .thenReturn(List.of(task));

        service.cleanupExpired();

        verify(derivedAssetStorageService, never()).deleteDerivedFileNode(any());
        verify(taskRepository).delete(task);
    }

    @Test
    void cleanupSkipsWhenRetentionDisabled() {
        properties.setEnabled(false);
        properties.setMaxAge(Duration.ofDays(7));

        service.cleanupExpired();

        verify(taskRepository, never()).findTerminalBefore(any(), any(), any());
    }

    private PhotoBatchTask task(String result) {
        PhotoBatchTask task = new PhotoBatchTask();
        task.setId(UUID.randomUUID());
        task.setStatus("COMPLETED");
        task.setResult(result);
        return task;
    }
}
