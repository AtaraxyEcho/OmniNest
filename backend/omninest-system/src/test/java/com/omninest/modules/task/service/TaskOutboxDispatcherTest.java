package com.omninest.modules.task.service;

import static org.mockito.Mockito.doNothing;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.modules.task.config.TaskOutboxProperties;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentMatchers;

class TaskOutboxDispatcherTest {

    private static final UUID DISPATCH_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID TASK_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");
    private static final UUID ID_A = UUID.fromString("10000000-0000-0000-0000-00000000000a");
    private static final UUID ID_B = UUID.fromString("10000000-0000-0000-0000-00000000000b");
    private static final UUID ID_C = UUID.fromString("10000000-0000-0000-0000-00000000000c");

    private final TaskDispatchService dispatchService = mock(TaskDispatchService.class);
    private final RabbitTaskDispatchPublisher publisher = mock(RabbitTaskDispatchPublisher.class);
    private final TaskOutboxProperties properties = new TaskOutboxProperties();
    private TaskOutboxDispatcher dispatcher;

    @BeforeEach
    void setUp() {
        properties.setEnabled(true);
        dispatcher = new TaskOutboxDispatcher(dispatchService, publisher, properties);
    }

    @Test
    void brokerRecoveryPublishesNextClaimAfterRetryableFailure() {
        ClaimedTaskDispatch first = dispatch(0, null);
        ClaimedTaskDispatch retry = dispatch(1, "BROKER_UNAVAILABLE");
        when(dispatchService.claimBatch(ArgumentMatchers.any(Instant.class)))
                .thenReturn(List.of(first))
                .thenReturn(List.of(retry));
        when(dispatchService.isDeadLetterPending(first)).thenReturn(false);
        when(dispatchService.isDeadLetterPending(retry)).thenReturn(false);
        when(dispatchService.requiresDeadLetter(first, true)).thenReturn(false);
        doThrow(publishFailure("BROKER_UNAVAILABLE", true)).doNothing().when(publisher).publish(first);
        doNothing().when(publisher).publish(retry);
        when(dispatchService.markPublishedBatch(
                ArgumentMatchers.eq(List.of(DISPATCH_ID)),
                ArgumentMatchers.any(Instant.class)))
                .thenReturn(1);

        dispatcher.dispatch();
        dispatcher.dispatch();

        verify(dispatchService).markFailed(
                ArgumentMatchers.eq(first),
                ArgumentMatchers.any(Instant.class),
                ArgumentMatchers.eq("BROKER_UNAVAILABLE")
        );
        verify(dispatchService).markPublishedBatch(
                ArgumentMatchers.eq(List.of(DISPATCH_ID)),
                ArgumentMatchers.any(Instant.class)
        );
    }

    @Test
    void successfulBatchIsSettledWithASingleStateUpdate() {
        List<ClaimedTaskDispatch> claimed = List.of(
                dispatch(ID_A, 0, null),
                dispatch(ID_B, 0, null),
                dispatch(ID_C, 0, null)
        );
        when(dispatchService.claimBatch(ArgumentMatchers.any(Instant.class))).thenReturn(claimed);
        claimed.forEach(dispatch -> when(dispatchService.isDeadLetterPending(dispatch)).thenReturn(false));
        doNothing().when(publisher).publish(ArgumentMatchers.any(ClaimedTaskDispatch.class));
        when(dispatchService.markPublishedBatch(
                ArgumentMatchers.anyList(),
                ArgumentMatchers.any(Instant.class)))
                .thenReturn(claimed.size());

        dispatcher.dispatch();

        verify(dispatchService).markPublishedBatch(
                ArgumentMatchers.eq(List.of(ID_A, ID_B, ID_C)),
                ArgumentMatchers.any(Instant.class)
        );
    }

    @Test
    void failedDispatchIsExcludedFromTheSettledBatch() {
        ClaimedTaskDispatch succeeded = dispatch(ID_A, 0, null);
        ClaimedTaskDispatch rejected = dispatch(ID_B, 0, null);
        when(dispatchService.claimBatch(ArgumentMatchers.any(Instant.class)))
                .thenReturn(List.of(succeeded, rejected));
        when(dispatchService.isDeadLetterPending(succeeded)).thenReturn(false);
        when(dispatchService.isDeadLetterPending(rejected)).thenReturn(false);
        when(dispatchService.requiresDeadLetter(succeeded, true)).thenReturn(false);
        when(dispatchService.requiresDeadLetter(rejected, true)).thenReturn(false);
        doNothing().when(publisher).publish(succeeded);
        doThrow(publishFailure("BROKER_UNAVAILABLE", true)).when(publisher).publish(rejected);
        when(dispatchService.markPublishedBatch(
                ArgumentMatchers.anyList(),
                ArgumentMatchers.any(Instant.class)))
                .thenReturn(1);

        dispatcher.dispatch();

        verify(dispatchService).markPublishedBatch(
                ArgumentMatchers.eq(List.of(ID_A)),
                ArgumentMatchers.any(Instant.class)
        );
        verify(dispatchService).markFailed(
                ArgumentMatchers.eq(rejected),
                ArgumentMatchers.any(Instant.class),
                ArgumentMatchers.eq("BROKER_UNAVAILABLE")
        );
    }

    @Test
    void exhaustedFailurePublishesDeadLetterAndCompletesOutbox() {
        ClaimedTaskDispatch dispatch = dispatch(3, "BROKER_NACK");
        when(dispatchService.claimBatch(ArgumentMatchers.any(Instant.class))).thenReturn(List.of(dispatch));
        when(dispatchService.isDeadLetterPending(dispatch)).thenReturn(false);
        when(dispatchService.requiresDeadLetter(dispatch, true)).thenReturn(true);
        doThrow(publishFailure("BROKER_NACK", true)).when(publisher).publish(dispatch);
        when(dispatchService.markDeadLetterPublished(
                ArgumentMatchers.eq(dispatch),
                ArgumentMatchers.any(Instant.class),
                ArgumentMatchers.eq("BROKER_NACK")
        )).thenReturn(true);

        dispatcher.dispatch();

        verify(publisher).publishDeadLetter(
                ArgumentMatchers.eq(dispatch),
                ArgumentMatchers.eq("BROKER_NACK"),
                ArgumentMatchers.eq("BROKER_NACK"),
                ArgumentMatchers.any(Instant.class)
        );
        verify(dispatchService).markDeadLetterPublished(
                ArgumentMatchers.eq(dispatch),
                ArgumentMatchers.any(Instant.class),
                ArgumentMatchers.eq("BROKER_NACK")
        );
    }

    @Test
    void deadLetterFailureRemainsRecoverableWithoutRepublishingOriginalMessage() {
        ClaimedTaskDispatch dispatch = dispatch(3, "DLQ_PENDING:MESSAGE_UNROUTABLE");
        when(dispatchService.claimBatch(ArgumentMatchers.any(Instant.class))).thenReturn(List.of(dispatch));
        when(dispatchService.isDeadLetterPending(dispatch)).thenReturn(true);
        when(dispatchService.deadLetterErrorCode(dispatch)).thenReturn("MESSAGE_UNROUTABLE");
        doThrow(publishFailure("BROKER_UNAVAILABLE", true))
                .when(publisher)
                .publishDeadLetter(
                        ArgumentMatchers.eq(dispatch),
                        ArgumentMatchers.eq("MESSAGE_UNROUTABLE"),
                        ArgumentMatchers.eq("DEAD_LETTER_RETRY"),
                        ArgumentMatchers.any(Instant.class)
                );

        dispatcher.dispatch();

        verify(publisher, never()).publish(dispatch);
        verify(dispatchService).markDeadLetterPublishFailed(
                ArgumentMatchers.eq(dispatch),
                ArgumentMatchers.any(Instant.class),
                ArgumentMatchers.eq("MESSAGE_UNROUTABLE")
        );
    }

    private TaskDispatchPublishException publishFailure(String errorCode, boolean retryable) {
        return new TaskDispatchPublishException(errorCode, retryable, errorCode, errorCode, null);
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

    private ClaimedTaskDispatch dispatch(UUID dispatchId, int attemptCount, String lastErrorCode) {
        return new ClaimedTaskDispatch(
                dispatchId,
                TASK_ID,
                "omni.task",
                "reader.parse",
                "{\"taskId\":\"" + TASK_ID + "\"}",
                attemptCount,
                lastErrorCode
        );
    }
}
