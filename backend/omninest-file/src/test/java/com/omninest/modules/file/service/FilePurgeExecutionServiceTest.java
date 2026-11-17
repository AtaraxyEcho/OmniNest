package com.omninest.modules.file.service;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.modules.file.domain.FilePurgeEntry;
import com.omninest.modules.file.event.FilePurgeRequestedEvent;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.Test;

/**
 * 文件永久删除 Worker 编排服务测试。
 *
 * @author OmniNest
 */
class FilePurgeExecutionServiceTest {
    private static final UUID TASK_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID OWNER_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");
    private static final UUID ROOT_NODE_ID = UUID.fromString("30000000-0000-0000-0000-000000000001");

    private final FilePurgeStateService stateService = mock(FilePurgeStateService.class);
    private final ObjectStorageClient objectStorageClient = mock(ObjectStorageClient.class);
    private final FilePurgeExecutionService executionService = new FilePurgeExecutionService(
            stateService,
            objectStorageClient
    );

    @Test
    void executePropagatesParallelDeleteFailureWithoutReselectingFailedEntries() {
        FilePurgeRequestedEvent event = new FilePurgeRequestedEvent(TASK_ID, OWNER_ID, ROOT_NODE_ID);
        List<FilePurgeEntry> entries = List.of(entry("first-object"), entry("second-object"));
        when(stateService.markRunning(event)).thenReturn(true);
        when(stateService.nextEntries(TASK_ID)).thenReturn(entries);
        when(objectStorageClient.objectExists(any())).thenThrow(new IllegalStateException("storage unavailable"));

        assertThatThrownBy(() -> executionService.execute(event))
                .isInstanceOf(IllegalStateException.class)
                .hasMessage("storage unavailable");

        verify(stateService, times(1)).nextEntries(TASK_ID);
        verify(stateService, times(2)).markEntryFailed(any(), any());
        verify(stateService).updateDeletingProgress(TASK_ID);
        verify(stateService, never()).markVerifying(TASK_ID);
        verify(stateService, never()).finalizePurge(event);
    }

    private FilePurgeEntry entry(String objectKey) {
        FilePurgeEntry entry = new FilePurgeEntry();
        entry.setId(UUID.randomUUID());
        entry.setBucketName("omninest");
        entry.setObjectKey(objectKey);
        return entry;
    }
}
