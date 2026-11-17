package com.omninest.modules.task.service;

import com.omninest.common.messaging.QueueNames;
import java.time.Instant;
import java.util.UUID;
import org.assertj.core.api.Assertions;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentMatchers;
import org.mockito.Mockito;

/**
 * Worker 消费失败重试与死信裁决测试。
 *
 * @author OmniNest
 */
class TaskFailureRetryServiceTest {

    private final TaskRecordService taskRecordService = Mockito.mock(TaskRecordService.class);
    private final TaskDispatchService taskDispatchService = Mockito.mock(TaskDispatchService.class);
    private final TaskFailureRetryService service =
            new TaskFailureRetryService(taskRecordService, taskDispatchService);

    @Test
    void schedulesNextAttemptWithBackoffWhenRetriesRemain() {
        UUID taskId = UUID.randomUUID();
        Object event = new Object();
        Instant nextRetryAt = Instant.now().plusSeconds(60);
        Mockito.when(taskRecordService.resolveFailure(
                        ArgumentMatchers.eq(taskId),
                        ArgumentMatchers.anyString(),
                        ArgumentMatchers.anyString(),
                        ArgumentMatchers.any(Instant.class)))
                .thenReturn(new FailureResolution(true, false, 1, nextRetryAt));

        TaskFailureRetryService.FailureOutcome outcome = service.handleFailure(
                taskId, QueueNames.VIDEO_TRANSCODE_ROUTING_KEY, event, new IllegalStateException("ffmpeg"));

        Assertions.assertThat(outcome).isEqualTo(TaskFailureRetryService.FailureOutcome.RETRY_SCHEDULED);
        Mockito.verify(taskDispatchService).enqueueAt(
                taskId,
                QueueNames.TASK_EXCHANGE,
                QueueNames.VIDEO_TRANSCODE_ROUTING_KEY,
                event,
                nextRetryAt
        );
    }

    @Test
    void doesNotRedeliverWhenRetriesAreExhausted() {
        UUID taskId = UUID.randomUUID();
        Mockito.when(taskRecordService.resolveFailure(
                        ArgumentMatchers.eq(taskId),
                        ArgumentMatchers.anyString(),
                        ArgumentMatchers.anyString(),
                        ArgumentMatchers.any(Instant.class)))
                .thenReturn(new FailureResolution(true, true, 3, null));

        TaskFailureRetryService.FailureOutcome outcome = service.handleFailure(
                taskId, QueueNames.PHOTO_SCAN_ROUTING_KEY, new Object(), new IllegalStateException("scan"));

        Assertions.assertThat(outcome).isEqualTo(TaskFailureRetryService.FailureOutcome.DEAD_LETTERED);
        Mockito.verifyNoInteractions(taskDispatchService);
    }

    @Test
    void ignoresFailureWhenTaskIsMissingOrTerminal() {
        UUID taskId = UUID.randomUUID();
        Mockito.when(taskRecordService.resolveFailure(
                        ArgumentMatchers.eq(taskId),
                        ArgumentMatchers.anyString(),
                        ArgumentMatchers.anyString(),
                        ArgumentMatchers.any(Instant.class)))
                .thenReturn(FailureResolution.ignored());

        TaskFailureRetryService.FailureOutcome outcome = service.handleFailure(
                taskId, QueueNames.PHOTO_BATCH_ROUTING_KEY, new Object(), new IllegalStateException("late"));

        Assertions.assertThat(outcome).isEqualTo(TaskFailureRetryService.FailureOutcome.IGNORED);
        Mockito.verifyNoInteractions(taskDispatchService);
    }
}
