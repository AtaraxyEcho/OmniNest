package com.omninest.worker.photos;

import static org.assertj.core.api.Assertions.assertThat;

import com.omninest.common.error.BusinessException;
import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.photos.event.PhotoAiEvent;
import com.omninest.modules.photos.event.PhotoAiEvent.Mode;
import com.omninest.modules.task.service.StaleTaskRecovery;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import java.time.Duration;
import java.time.Instant;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.Mockito;

/**
 * 照片图像分析任务失败重试与心跳恢复测试。
 *
 * @author OmniNest
 */
class PhotoAiTaskRetryServiceTest {

    private static final String TASK_TYPE = "PHOTO_AI_ANALYSIS";

    private TaskRecordService taskRecordService;
    private TaskDispatchService taskDispatchService;
    private PhotoAiTaskRetryService service;

    @BeforeEach
    void setUp() {
        taskRecordService = Mockito.mock(TaskRecordService.class);
        taskDispatchService = Mockito.mock(TaskDispatchService.class);
        service = new PhotoAiTaskRetryService(taskRecordService, taskDispatchService);
    }

    @Test
    void handleFailureSchedulesDelayedRetryForTransientErrors() {
        PhotoAiEvent event = event();

        service.handlePhotoAiFailure(event, new IllegalStateException("sidecar unavailable"));

        Mockito.verify(taskRecordService).markRetryWait(
                Mockito.eq(event.taskId()),
                Mockito.eq("IllegalStateException"),
                Mockito.any(Instant.class));
        ArgumentCaptor<Instant> retryAtCaptor = ArgumentCaptor.forClass(Instant.class);
        Mockito.verify(taskDispatchService).enqueueAt(
                Mockito.eq(event.taskId()),
                Mockito.eq(QueueNames.TASK_EXCHANGE),
                Mockito.eq(QueueNames.PHOTO_AI_ROUTING_KEY),
                Mockito.eq(event),
                retryAtCaptor.capture());
        Instant firstRetryAt = Instant.now().plus(Duration.ofMinutes(1));
        assertThat(retryAtCaptor.getValue())
                .isAfter(Instant.now())
                .isBefore(firstRetryAt.plusSeconds(5));
    }

    @Test
    void handleFailureDeadLettersBusinessErrorsWithoutRetry() {
        PhotoAiEvent event = event();

        service.handlePhotoAiFailure(event, new BusinessException(
                com.omninest.common.enums.ErrorCode.BAD_REQUEST, "不支持的模式"));

        Mockito.verify(taskRecordService).markDeadLetter(
                Mockito.eq(event.taskId()), Mockito.eq("BAD_REQUEST"), Mockito.anyString());
        Mockito.verifyNoInteractions(taskDispatchService);
    }

    @Test
    void handleFailureUsesShortRetryLadderForDependencyNotReady() {
        PhotoAiEvent event = event();

        service.handlePhotoAiFailure(event, new BusinessException(
                com.omninest.common.enums.ErrorCode.TASK_DEPENDENCY_NOT_READY, "照片封面尚未生成，等待缩略图任务回填"));

        Mockito.verify(taskRecordService).markRetryWait(
                Mockito.eq(event.taskId()),
                Mockito.eq("TASK_DEPENDENCY_NOT_READY"),
                Mockito.any(Instant.class));
        Mockito.verify(taskRecordService, Mockito.never()).markDeadLetter(
                Mockito.any(UUID.class), Mockito.anyString(), Mockito.any());
        ArgumentCaptor<Instant> retryAtCaptor = ArgumentCaptor.forClass(Instant.class);
        Mockito.verify(taskDispatchService).enqueueAt(
                Mockito.eq(event.taskId()),
                Mockito.eq(QueueNames.TASK_EXCHANGE),
                Mockito.eq(QueueNames.PHOTO_AI_ROUTING_KEY),
                Mockito.eq(event),
                retryAtCaptor.capture());
        assertThat(retryAtCaptor.getValue())
                .isAfter(Instant.now())
                .isBefore(Instant.now().plusSeconds(15));
    }

    @Test
    void handleFailureDeadLettersDependencyNotReadyWhenMaxRetriesReached() {
        PhotoAiEvent event = event();
        Mockito.when(taskRecordService.retryCount(event.taskId())).thenReturn(3);

        service.handlePhotoAiFailure(event, new BusinessException(
                com.omninest.common.enums.ErrorCode.TASK_DEPENDENCY_NOT_READY, "照片封面尚未生成，等待缩略图任务回填"));

        Mockito.verify(taskRecordService).markDeadLetter(
                Mockito.eq(event.taskId()), Mockito.eq("TASK_DEPENDENCY_NOT_READY"), Mockito.anyString());
        Mockito.verify(taskRecordService, Mockito.never()).markRetryWait(
                Mockito.any(UUID.class), Mockito.anyString(), Mockito.any(Instant.class));
        Mockito.verifyNoInteractions(taskDispatchService);
    }

    @Test
    void handleFailureDeadLettersWhenMaxRetriesReached() {
        PhotoAiEvent event = event();
        Mockito.when(taskRecordService.retryCount(event.taskId())).thenReturn(3);

        service.handlePhotoAiFailure(event, new IllegalStateException("sidecar unavailable"));

        Mockito.verify(taskRecordService).markDeadLetter(
                Mockito.eq(event.taskId()), Mockito.eq("IllegalStateException"), Mockito.anyString());
        Mockito.verify(taskRecordService, Mockito.never()).markRetryWait(
                Mockito.any(UUID.class), Mockito.anyString(), Mockito.any(Instant.class));
        Mockito.verifyNoInteractions(taskDispatchService);
    }

    @Test
    void handleFailureIgnoresLegacyEventsWithoutTaskId() {
        PhotoAiEvent event = new PhotoAiEvent(null, UUID.randomUUID(), UUID.randomUUID(), Mode.SINGLE_PHOTO);

        service.handlePhotoAiFailure(event, new IllegalStateException("sidecar unavailable"));

        Mockito.verifyNoInteractions(taskRecordService, taskDispatchService);
    }

    @Test
    void recoverStaleTaskRebuildsEventFromPayloadAndEnqueuesRetry() {
        UUID taskId = UUID.randomUUID();
        UUID ownerUserId = UUID.randomUUID();
        UUID photoId = UUID.randomUUID();
        Instant nextRetryAt = Instant.now().plus(Duration.ofMinutes(5));
        Map<String, Object> payload = new HashMap<>();
        payload.put("ownerUserId", ownerUserId.toString());
        payload.put("mode", Mode.SINGLE_PHOTO.name());
        payload.put("photoId", photoId.toString());
        Mockito.when(taskRecordService.taskPayload(taskId)).thenReturn(payload);
        Mockito.when(taskRecordService.recoverStaleTask(
                        Mockito.eq(taskId), Mockito.eq(TASK_TYPE),
                        Mockito.any(Instant.class), Mockito.any(Instant.class),
                        Mockito.eq("WORKER_HEARTBEAT_TIMEOUT")))
                .thenReturn(new StaleTaskRecovery(true, false, ownerUserId, null, 1, nextRetryAt));

        service.recoverStaleTask(taskId, TASK_TYPE, Instant.now().minusSeconds(300));

        ArgumentCaptor<PhotoAiEvent> eventCaptor = ArgumentCaptor.forClass(PhotoAiEvent.class);
        Mockito.verify(taskDispatchService).enqueueAt(
                Mockito.eq(taskId),
                Mockito.eq(QueueNames.TASK_EXCHANGE),
                Mockito.eq(QueueNames.PHOTO_AI_ROUTING_KEY),
                eventCaptor.capture(),
                Mockito.eq(nextRetryAt));
        assertThat(eventCaptor.getValue().taskId()).isEqualTo(taskId);
        assertThat(eventCaptor.getValue().ownerUserId()).isEqualTo(ownerUserId);
        assertThat(eventCaptor.getValue().photoId()).isEqualTo(photoId);
        assertThat(eventCaptor.getValue().mode()).isEqualTo(Mode.SINGLE_PHOTO);
    }

    @Test
    void recoverStaleTaskDoesNotEnqueueWhenDeadLetter() {
        UUID taskId = UUID.randomUUID();
        Mockito.when(taskRecordService.taskPayload(taskId)).thenReturn(Map.of(
                "ownerUserId", UUID.randomUUID().toString(),
                "mode", Mode.FACE_RECLUSTER.name()));
        Mockito.when(taskRecordService.recoverStaleTask(
                        Mockito.eq(taskId), Mockito.eq(TASK_TYPE),
                        Mockito.any(Instant.class), Mockito.any(Instant.class),
                        Mockito.eq("WORKER_HEARTBEAT_TIMEOUT")))
                .thenReturn(new StaleTaskRecovery(true, true, UUID.randomUUID(), null, 3, null));

        service.recoverStaleTask(taskId, TASK_TYPE, Instant.now().minusSeconds(300));

        Mockito.verifyNoInteractions(taskDispatchService);
    }

    private PhotoAiEvent event() {
        return new PhotoAiEvent(
                UUID.randomUUID(),
                UUID.randomUUID(),
                UUID.randomUUID(),
                Mode.SINGLE_PHOTO
        );
    }
}
