package com.omninest.modules.task.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.mock;

import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.task.config.TaskOutboxProperties;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.ArgumentMatchers;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.core.ReturnedMessage;
import org.springframework.amqp.rabbit.connection.CorrelationData;
import org.springframework.amqp.rabbit.core.RabbitTemplate;

class RabbitTaskDispatchPublisherTest {

    private static final UUID DISPATCH_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID TASK_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");
    private static final Instant NOW = Instant.parse("2026-08-25T00:00:00Z");

    private final RabbitTemplate rabbitTemplate = mock(RabbitTemplate.class);
    private final TaskOutboxProperties properties = new TaskOutboxProperties();
    private RabbitTaskDispatchPublisher publisher;

    @BeforeEach
    void setUp() {
        properties.setConfirmTimeoutMillis(20L);
        properties.setInstanceId("api-test-1");
        publisher = new RabbitTaskDispatchPublisher(rabbitTemplate, properties);
    }

    @Test
    void acknowledgedPublishCompletesNormally() {
        completeConfirm(true, false);

        publisher.publish(dispatch("{\"taskId\":\"" + TASK_ID + "\"}"));
    }

    @Test
    void brokerNackUsesStableRetryableError() {
        completeConfirm(false, false);

        assertPublishFailure("BROKER_NACK", true, () -> publisher.publish(dispatch("{}")));
    }

    @Test
    void returnedMessageUsesStableRetryableError() {
        completeConfirm(true, true);

        assertPublishFailure("MESSAGE_UNROUTABLE", true, () -> publisher.publish(dispatch("{}")));
    }

    @Test
    void missingConfirmTimesOutWithStableError() {
        assertPublishFailure("CONFIRM_TIMEOUT", true, () -> publisher.publish(dispatch("{}")));
    }

    @Test
    void malformedPayloadIsPermanentFailure() {
        assertPublishFailure("PAYLOAD_INVALID", false, () -> publisher.publish(dispatch("{")));
    }

    @Test
    void deadLetterRedactsSensitivePayloadFields() {
        ArgumentCaptor<Object> payloadCaptor = ArgumentCaptor.forClass(Object.class);
        doAnswer(invocation -> {
            CorrelationData correlationData = invocation.getArgument(3);
            correlationData.getFuture().complete(new CorrelationData.Confirm(true, null));
            return null;
        }).when(rabbitTemplate).convertAndSend(
                ArgumentMatchers.eq(QueueNames.DEAD_LETTER_EXCHANGE),
                ArgumentMatchers.eq(QueueNames.DEAD_LETTER_ROUTING_KEY),
                payloadCaptor.capture(),
                ArgumentMatchers.any(CorrelationData.class)
        );

        publisher.publishDeadLetter(
                dispatch("{\"taskId\":\"" + TASK_ID + "\",\"token\":\"secret-value\"}"),
                "BROKER_NACK",
                "BROKER_NACK",
                NOW
        );

        TaskDispatchDeadLetter deadLetter = (TaskDispatchDeadLetter) payloadCaptor.getValue();
        assertThat(deadLetter.taskId()).isEqualTo(TASK_ID);
        assertThat(deadLetter.errorCode()).isEqualTo("BROKER_NACK");
        assertThat(deadLetter.publisherInstanceId()).isEqualTo("api-test-1");
        Map<?, ?> sanitizedPayload = (Map<?, ?>) deadLetter.sanitizedPayload();
        assertThat(sanitizedPayload.get("token")).isEqualTo("[REDACTED]");
        assertThat(sanitizedPayload.get("taskId")).isEqualTo(TASK_ID.toString());
    }

    private void completeConfirm(boolean ack, boolean returned) {
        doAnswer(invocation -> {
            CorrelationData correlationData = invocation.getArgument(3);
            if (returned) {
                correlationData.setReturned(new ReturnedMessage(
                        new Message("body".getBytes(StandardCharsets.UTF_8)),
                        312,
                        "NO_ROUTE",
                        "omni.task",
                        "missing.route"
                ));
            }
            correlationData.getFuture().complete(new CorrelationData.Confirm(ack, ack ? null : "nack"));
            return null;
        }).when(rabbitTemplate).convertAndSend(
                ArgumentMatchers.anyString(),
                ArgumentMatchers.anyString(),
                ArgumentMatchers.any(Object.class),
                ArgumentMatchers.any(CorrelationData.class)
        );
    }

    private void assertPublishFailure(String errorCode, boolean retryable, Runnable operation) {
        assertThatThrownBy(operation::run)
                .isInstanceOfSatisfying(TaskDispatchPublishException.class, exception -> {
                    assertThat(exception.errorCode()).isEqualTo(errorCode);
                    assertThat(exception.retryable()).isEqualTo(retryable);
                });
    }

    private ClaimedTaskDispatch dispatch(String payload) {
        return new ClaimedTaskDispatch(
                DISPATCH_ID,
                TASK_ID,
                "omni.task",
                "reader.parse",
                payload,
                0,
                null
        );
    }
}
