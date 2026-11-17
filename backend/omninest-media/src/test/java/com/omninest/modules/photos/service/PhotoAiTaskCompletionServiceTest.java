package com.omninest.modules.photos.service;

import static org.assertj.core.api.Assertions.assertThat;

import com.omninest.common.sync.SyncScope;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.photos.event.PhotoAiEvent.Mode;
import com.omninest.modules.task.service.TaskRecordService;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.InOrder;
import org.mockito.Mockito;

/**
 * 照片 AI 任务完成事务编排测试。
 *
 * @author OmniNest
 */
class PhotoAiTaskCompletionServiceTest {

    @Test
    void completePersistsTaskBeforeRecordingInvalidation() {
        TaskRecordService taskRecordService = Mockito.mock(TaskRecordService.class);
        MediaSyncEventService syncEventService = Mockito.mock(MediaSyncEventService.class);
        PhotoAiTaskCompletionService service = new PhotoAiTaskCompletionService(
                taskRecordService,
                syncEventService
        );
        UUID taskId = UUID.randomUUID();
        UUID ownerUserId = UUID.randomUUID();
        Map<String, Object> result = Map.of("processedItems", 2L);

        service.complete(taskId, ownerUserId, Mode.LIBRARY_REANALYSIS, result, 2L, 0L);

        InOrder inOrder = Mockito.inOrder(taskRecordService, syncEventService);
        inOrder.verify(taskRecordService).markCompleted(taskId, result);
        ArgumentCaptor<Map<String, Object>> hintsCaptor = mapCaptor();
        inOrder.verify(syncEventService).invalidate(
                Mockito.eq(ownerUserId),
                Mockito.eq(SyncScope.PHOTOS),
                Mockito.eq("PHOTO_AI_RESULTS"),
                hintsCaptor.capture()
        );
        assertThat(hintsCaptor.getValue())
                .containsEntry("resourceId", taskId.toString())
                .containsEntry("mode", Mode.LIBRARY_REANALYSIS.name())
                .containsEntry("succeededItems", 2L)
                .containsEntry("failedItems", 0L);
    }

    @SuppressWarnings("unchecked")
    private ArgumentCaptor<Map<String, Object>> mapCaptor() {
        return ArgumentCaptor.forClass(Map.class);
    }
}
