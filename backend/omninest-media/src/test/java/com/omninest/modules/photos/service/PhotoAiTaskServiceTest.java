package com.omninest.modules.photos.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.photos.dto.PhotoDtos.PhotoAiTaskDto;
import com.omninest.modules.photos.event.PhotoAiEvent;
import com.omninest.modules.photos.event.PhotoAiEvent.Mode;
import com.omninest.modules.photos.repository.PhotoItemRepository;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.ArgumentMatchers;
import org.mockito.Mockito;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.Pageable;

/**
 * 照片 AI 异步任务编排测试。
 *
 * @author OmniNest
 */
class PhotoAiTaskServiceTest {

    private PhotoAiService photoAiService;
    private PhotoItemRepository photoItemRepository;
    private PhotosRuntimeConfigService configService;
    private TaskRecordService taskRecordService;
    private TaskDispatchService taskDispatchService;
    private PhotoAiTaskCompletionService completionService;
    private PhotoAiTaskService service;

    @BeforeEach
    void setUp() {
        photoAiService = Mockito.mock(PhotoAiService.class);
        photoItemRepository = Mockito.mock(PhotoItemRepository.class);
        configService = Mockito.mock(PhotosRuntimeConfigService.class);
        taskRecordService = Mockito.mock(TaskRecordService.class);
        taskDispatchService = Mockito.mock(TaskDispatchService.class);
        completionService = Mockito.mock(PhotoAiTaskCompletionService.class);
        service = new PhotoAiTaskService(
                photoAiService,
                photoItemRepository,
                configService,
                taskRecordService,
                taskDispatchService,
                completionService
        );
        Mockito.when(taskRecordService.claimForExecution(Mockito.any(UUID.class), Mockito.any(String.class)))
                .thenReturn(true);
    }

    @Test
    void queueLibraryReanalysisCreatesTaskBeforePublishingEvent() {
        UUID ownerUserId = UUID.randomUUID();
        Mockito.when(photoItemRepository.countByOwnerUserId(ownerUserId)).thenReturn(12L);

        PhotoAiTaskDto task = service.queueLibraryReanalysis(ownerUserId);

        assertThat(task.status()).isEqualTo("QUEUED");
        assertThat(task.totalItems()).isEqualTo(12L);
        Mockito.verify(taskRecordService).createQueuedTask(
                Mockito.eq(task.taskId()),
                Mockito.eq(ownerUserId),
                Mockito.eq("PHOTO_AI_REANALYSIS"),
                Mockito.eq(QueueNames.PHOTO_AI_ROUTING_KEY),
                ArgumentMatchers.argThat(payload -> Mode.LIBRARY_REANALYSIS.name().equals(payload.get("mode")))
        );
        ArgumentCaptor<PhotoAiEvent> eventCaptor = ArgumentCaptor.forClass(PhotoAiEvent.class);
        Mockito.verify(taskDispatchService).enqueue(
                Mockito.eq(task.taskId()),
                Mockito.eq(QueueNames.TASK_EXCHANGE),
                Mockito.eq(QueueNames.PHOTO_AI_ROUTING_KEY),
                eventCaptor.capture()
        );
        assertThat(eventCaptor.getValue().taskId()).isEqualTo(task.taskId());
        assertThat(eventCaptor.getValue().mode()).isEqualTo(Mode.LIBRARY_REANALYSIS);
    }

    @Test
    void executeSinglePhotoCompletesTaskAndInvalidatesPhotoScope() {
        UUID taskId = UUID.randomUUID();
        UUID ownerUserId = UUID.randomUUID();
        UUID photoId = UUID.randomUUID();
        Mockito.when(configService.isAiEnabled()).thenReturn(true);

        service.execute(new PhotoAiEvent(taskId, ownerUserId, photoId, Mode.SINGLE_PHOTO));

        Mockito.verify(taskRecordService).claimForExecution(taskId, "AI_ANALYSIS");
        Mockito.verify(photoAiService).processPhoto(ownerUserId, photoId);
        Mockito.verify(completionService).complete(
                Mockito.eq(taskId),
                Mockito.eq(ownerUserId),
                Mockito.eq(Mode.SINGLE_PHOTO),
                ArgumentMatchers.argThat(result -> Integer.valueOf(1).equals(result.get("processedItems"))),
                Mockito.eq(1L),
                Mockito.eq(0L)
        );
    }

    @Test
    void executeLibraryReanalysisContinuesAfterIndividualFailure() {
        UUID taskId = UUID.randomUUID();
        UUID ownerUserId = UUID.randomUUID();
        UUID failedPhotoId = UUID.randomUUID();
        UUID successfulPhotoId = UUID.randomUUID();
        Mockito.when(configService.isAiEnabled()).thenReturn(true);
        Mockito.when(photoItemRepository.countByOwnerUserId(ownerUserId)).thenReturn(2L);
        Mockito.when(photoItemRepository.findIdsByOwnerUserId(
                        Mockito.eq(ownerUserId),
                        ArgumentMatchers.any(Pageable.class)))
                .thenReturn(new PageImpl<>(List.of(failedPhotoId, successfulPhotoId)));
        Mockito.doThrow(new IllegalStateException("sidecar rejected image"))
                .when(photoAiService).processPhoto(ownerUserId, failedPhotoId);

        service.execute(new PhotoAiEvent(taskId, ownerUserId, null, Mode.LIBRARY_REANALYSIS));

        Mockito.verify(photoAiService).processPhoto(ownerUserId, successfulPhotoId);
        Mockito.verify(photoAiService).clusterFaces(ownerUserId);
        ArgumentCaptor<Map<String, Object>> resultCaptor = mapCaptor();
        Mockito.verify(completionService).complete(
                Mockito.eq(taskId),
                Mockito.eq(ownerUserId),
                Mockito.eq(Mode.LIBRARY_REANALYSIS),
                resultCaptor.capture(),
                Mockito.eq(1L),
                Mockito.eq(1L)
        );
        assertThat(resultCaptor.getValue())
                .containsEntry("processedItems", 2L)
                .containsEntry("succeededItems", 1L)
                .containsEntry("failedItems", 1L);
        assertThat((List<?>) resultCaptor.getValue().get("failedPhotoIds"))
                .extracting(Object::toString)
                .containsExactly(failedPhotoId.toString());
    }

    @Test
    void executeLibraryReanalysisFailsTaskWhenEveryPhotoFails() {
        UUID taskId = UUID.randomUUID();
        UUID ownerUserId = UUID.randomUUID();
        UUID photoId = UUID.randomUUID();
        Mockito.when(configService.isAiEnabled()).thenReturn(true);
        Mockito.when(photoItemRepository.countByOwnerUserId(ownerUserId)).thenReturn(1L);
        Mockito.when(photoItemRepository.findIdsByOwnerUserId(
                        Mockito.eq(ownerUserId),
                        ArgumentMatchers.any(Pageable.class)))
                .thenReturn(new PageImpl<>(List.of(photoId)));
        Mockito.doThrow(new IllegalStateException("sidecar unavailable"))
                .when(photoAiService).processPhoto(ownerUserId, photoId);

        assertThatThrownBy(() -> service.execute(
                new PhotoAiEvent(taskId, ownerUserId, null, Mode.LIBRARY_REANALYSIS)))
                .isInstanceOf(IllegalStateException.class)
                .hasMessage("照片图像分析重分析全部失败");

        Mockito.verify(taskRecordService, Mockito.never()).markFailed(Mockito.eq(taskId), Mockito.anyString());
        Mockito.verifyNoInteractions(completionService);
        Mockito.verify(photoAiService, Mockito.never()).clusterFaces(ownerUserId);
    }

    @Test
    void executeCancelsQueuedTaskWhenRuntimeFeatureIsDisabled() {
        UUID taskId = UUID.randomUUID();
        Mockito.when(configService.isAiEnabled()).thenReturn(false);

        service.execute(new PhotoAiEvent(taskId, UUID.randomUUID(), null, Mode.FACE_RECLUSTER));

        Mockito.verify(taskRecordService).markCancelled(taskId);
        Mockito.verifyNoInteractions(photoAiService);
    }

    @Test
    void executeCancelsSingleTaskWhenSourceFileIsPurging() {
        UUID taskId = UUID.randomUUID();
        UUID ownerUserId = UUID.randomUUID();
        UUID photoId = UUID.randomUUID();
        Mockito.when(configService.isAiEnabled()).thenReturn(true);
        Mockito.doThrow(new BusinessException(ErrorCode.FILE_LIFECYCLE_CONFLICT, "文件正在永久删除"))
                .when(photoAiService).processPhoto(ownerUserId, photoId);

        service.execute(new PhotoAiEvent(taskId, ownerUserId, photoId, Mode.SINGLE_PHOTO));

        Mockito.verify(taskRecordService).markCancelled(taskId);
        Mockito.verify(taskRecordService, Mockito.never()).markFailed(Mockito.eq(taskId), Mockito.anyString());
    }

    @SuppressWarnings("unchecked")
    private ArgumentCaptor<Map<String, Object>> mapCaptor() {
        return ArgumentCaptor.forClass(Map.class);
    }
}
