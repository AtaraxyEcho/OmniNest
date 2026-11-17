package com.omninest.modules.task.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.modules.task.config.TaskOutboxProperties;
import com.omninest.modules.task.domain.TaskDispatch;
import com.omninest.modules.task.repository.TaskDispatchRepository;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

class TaskDispatchServiceTest {

    private static final UUID DISPATCH_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID TASK_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");
    private static final Instant NOW = Instant.parse("2026-08-25T00:00:00Z");

    private final TaskDispatchRepository repository = mock(TaskDispatchRepository.class);
    private final TaskRecordService taskRecordService = mock(TaskRecordService.class);
    private final TaskOutboxProperties properties = new TaskOutboxProperties();
    private TaskDispatchService service;

    @BeforeEach
    void setUp() {
        properties.setInstanceId("api-test-1");
        service = new TaskDispatchService(repository, properties, taskRecordService);
    }

    @Test
    void firstThreeFailuresUseOneFiveAndFifteenMinuteDelays() {
        assertRetryDelay(0, NOW.plusSeconds(60), 1);
        assertRetryDelay(1, NOW.plusSeconds(300), 2);
        assertRetryDelay(2, NOW.plusSeconds(900), 3);
    }

    @Test
    void exhaustedOrPermanentFailureRequiresDeadLetter() {
        assertThat(service.requiresDeadLetter(dispatch(3, null), true)).isTrue();
        assertThat(service.requiresDeadLetter(dispatch(0, null), false)).isTrue();
        assertThat(service.requiresDeadLetter(dispatch(2, null), true)).isFalse();
    }

    @Test
    void confirmedDeadLetterCompletesOutboxAndMarksTaskDlq() {
        ClaimedTaskDispatch dispatch = dispatch(3, null);
        when(repository.markDeadLetterPublished(
                DISPATCH_ID,
                "api-test-1",
                4,
                NOW,
                "BROKER_NACK"
        )).thenReturn(1);

        boolean updated = service.markDeadLetterPublished(dispatch, NOW, "BROKER_NACK");

        assertThat(updated).isTrue();
        verify(taskRecordService).markDeadLetter(TASK_ID, "任务消息投递失败: BROKER_NACK");
    }

    @Test
    void failedDeadLetterPublishKeepsRecoverablePendingMarker() {
        ClaimedTaskDispatch dispatch = dispatch(0, null);
        when(repository.markFailed(
                DISPATCH_ID,
                "api-test-1",
                3,
                NOW.plusSeconds(900),
                "DLQ_PENDING:PAYLOAD_INVALID",
                NOW
        )).thenReturn(1);

        boolean updated = service.markDeadLetterPublishFailed(dispatch, NOW, "PAYLOAD_INVALID");

        assertThat(updated).isTrue();
    }

    @Test
    void deadLetterPendingMarkerRestoresOriginalErrorCode() {
        ClaimedTaskDispatch dispatch = dispatch(3, "DLQ_PENDING:MESSAGE_UNROUTABLE");

        assertThat(service.isDeadLetterPending(dispatch)).isTrue();
        assertThat(service.deadLetterErrorCode(dispatch)).isEqualTo("MESSAGE_UNROUTABLE");
    }

    @Test
    void enqueueAllWritesOneDispatchPerItemInSingleSaveAll() {
        UUID first = UUID.fromString("20000000-0000-0000-0000-000000000011");
        UUID second = UUID.fromString("20000000-0000-0000-0000-000000000012");

        service.enqueueAll("omni.task", "photo.index", List.of(
                new TaskDispatchItem(first, Map.of("photoId", first.toString())),
                new TaskDispatchItem(second, Map.of("photoId", second.toString()))));

        @SuppressWarnings("unchecked")
        ArgumentCaptor<List<TaskDispatch>> captor = ArgumentCaptor.forClass(List.class);
        verify(repository).saveAll(captor.capture());
        assertThat(captor.getValue())
                .extracting(TaskDispatch::getTaskId)
                .containsExactly(first, second);
        assertThat(captor.getValue()).allSatisfy(dispatch -> {
            assertThat(dispatch.getExchangeName()).isEqualTo("omni.task");
            assertThat(dispatch.getRoutingKey()).isEqualTo("photo.index");
            assertThat(dispatch.getPayload()).contains("\"photoId\"");
            assertThat(dispatch.getNextAttemptAt()).isNotNull();
        });
    }

    @Test
    void enqueueAllSkipsEmptyBatch() {
        service.enqueueAll("omni.task", "photo.index", List.of());

        verify(repository, never()).saveAll(anyList());
    }

    private void assertRetryDelay(int previousAttempts, Instant expectedNextAttemptAt, int expectedAttempts) {
        ClaimedTaskDispatch dispatch = dispatch(previousAttempts, null);
        ArgumentCaptor<Instant> nextAttemptCaptor = ArgumentCaptor.forClass(Instant.class);
        when(repository.markFailed(
                org.mockito.ArgumentMatchers.eq(DISPATCH_ID),
                org.mockito.ArgumentMatchers.eq("api-test-1"),
                org.mockito.ArgumentMatchers.eq(expectedAttempts),
                nextAttemptCaptor.capture(),
                org.mockito.ArgumentMatchers.eq("BROKER_UNAVAILABLE"),
                org.mockito.ArgumentMatchers.eq(NOW)
        )).thenReturn(1);

        assertThat(service.markFailed(dispatch, NOW, "BROKER_UNAVAILABLE")).isTrue();
        assertThat(nextAttemptCaptor.getValue()).isEqualTo(expectedNextAttemptAt);
    }

    private ClaimedTaskDispatch dispatch(int attemptCount, String lastErrorCode) {
        return new ClaimedTaskDispatch(
                DISPATCH_ID,
                TASK_ID,
                "omni.task",
                "reader.parse",
                "{\"taskId\":\"" + TASK_ID + "\"}",
                attemptCount,
                lastErrorCode
        );
    }
}
