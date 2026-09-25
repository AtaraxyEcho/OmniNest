package com.omninest.worker.dlq;

import com.omninest.modules.task.service.TaskRecordService;
import com.rabbitmq.client.Channel;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.UUID;
import org.assertj.core.api.Assertions;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.Mockito;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.core.MessageProperties;

/**
 * 死信队列消费者消息编排测试。
 *
 * @author OmniNest
 */
class DeadLetterConsumerTest {
    private final TaskRecordService taskRecordService = Mockito.mock(TaskRecordService.class);
    private final Channel channel = Mockito.mock(Channel.class);
    private final DeadLetterConsumer consumer = new DeadLetterConsumer(taskRecordService);

    @Test
    void handleUsesTaskIdHeaderAndAcknowledgesMessage() throws IOException {
        UUID taskId = UUID.randomUUID();
        Mockito.when(taskRecordService.markDeadLetter(Mockito.eq(taskId), Mockito.anyString(), Mockito.any()))
                .thenReturn(true);

        consumer.handle(message(taskId.toString(), "{}", "file.index"), channel);

        Mockito.verify(taskRecordService).markDeadLetter(
                Mockito.eq(taskId),
                Mockito.eq("消息进入死信队列，原始路由键: file.index"),
                Mockito.isNull()
        );
        Mockito.verify(channel).basicAck(1L, false);
    }

    @Test
    void handleRecordsDispatchFailureContextFromOutboxDeadLetter() throws IOException {
        UUID taskId = UUID.randomUUID();
        Mockito.when(taskRecordService.markDeadLetter(Mockito.eq(taskId), Mockito.anyString(), Mockito.any()))
                .thenReturn(true);
        String body = "{\"taskId\":\"" + taskId + "\",\"errorCode\":\"BROKER_UNAVAILABLE\","
                + "\"failureType\":\"AmqpConnectException\",\"instanceId\":\"api-1\","
                + "\"payload\":{\"taskId\":\"" + taskId + "\"}}";

        consumer.handle(message(taskId.toString(), body, "media.scrape"), channel);

        ArgumentCaptor<String> summaryCaptor = ArgumentCaptor.forClass(String.class);
        Mockito.verify(taskRecordService).markDeadLetter(
                Mockito.eq(taskId),
                summaryCaptor.capture(),
                Mockito.isNull()
        );
        Mockito.verify(channel).basicAck(1L, false);
        Assertions.assertThat(summaryCaptor.getValue())
                .contains("原始路由键: media.scrape")
                .contains("投递失败: AmqpConnectException/BROKER_UNAVAILABLE")
                .contains("@api-1")
                .contains("死信载荷:");
    }

    @Test
    void handlePassesStackSummaryFieldAsThirdArgument() throws IOException {
        UUID taskId = UUID.randomUUID();
        Mockito.when(taskRecordService.markDeadLetter(Mockito.eq(taskId), Mockito.anyString(), Mockito.any()))
                .thenReturn(true);
        String body = "{\"taskId\":\"" + taskId + "\",\"stackSummary\":\"java.lang.IllegalStateException: boom\"}";

        consumer.handle(message(taskId.toString(), body, "file.index"), channel);

        Mockito.verify(taskRecordService).markDeadLetter(
                Mockito.eq(taskId),
                Mockito.anyString(),
                Mockito.eq("java.lang.IllegalStateException: boom")
        );
        Mockito.verify(channel).basicAck(1L, false);
    }

    @Test
    void handleUsesTaskIdFromJsonBody() throws IOException {
        UUID taskId = UUID.randomUUID();
        Mockito.when(taskRecordService.markDeadLetter(Mockito.eq(taskId), Mockito.anyString(), Mockito.any()))
                .thenReturn(true);

        consumer.handle(message(null, "{\"taskId\":\"" + taskId + "\"}", "text.extract"), channel);

        Mockito.verify(taskRecordService).markDeadLetter(Mockito.eq(taskId), Mockito.anyString(), Mockito.isNull());
        Mockito.verify(channel).basicAck(1L, false);
    }

    @Test
    void handleFallsBackToBodyWhenHeaderIsInvalid() throws IOException {
        UUID taskId = UUID.randomUUID();
        Mockito.when(taskRecordService.markDeadLetter(Mockito.eq(taskId), Mockito.anyString(), Mockito.any()))
                .thenReturn(true);

        consumer.handle(message("invalid", "{\"taskId\":\"" + taskId + "\"}", "file.index"), channel);

        Mockito.verify(taskRecordService).markDeadLetter(Mockito.eq(taskId), Mockito.anyString(), Mockito.isNull());
        Mockito.verify(channel).basicAck(1L, false);
    }

    @Test
    void handleDoesNotTreatResourceIdAsTaskId() throws IOException {
        UUID taskId = UUID.randomUUID();

        consumer.handle(message(null, "{\"fileNodeId\":\"" + taskId + "\"}", "thumbnail.generate"), channel);

        Mockito.verifyNoInteractions(taskRecordService);
        Mockito.verify(channel).basicAck(1L, false);
    }

    @Test
    void handleAcknowledgesWhenTaskDoesNotExist() throws IOException {
        UUID taskId = UUID.randomUUID();
        Mockito.when(taskRecordService.markDeadLetter(Mockito.eq(taskId), Mockito.anyString(), Mockito.any()))
                .thenReturn(false);

        consumer.handle(message(taskId.toString(), "{}", "file.index"), channel);

        Mockito.verify(taskRecordService).markDeadLetter(Mockito.eq(taskId), Mockito.anyString(), Mockito.isNull());
        Mockito.verify(channel).basicAck(1L, false);
    }

    @Test
    void handleWithoutTaskIdDoesNotCallTaskService() throws IOException {
        consumer.handle(message(null, "{\"data\":\"none\"}", "unknown.key"), channel);

        Mockito.verifyNoInteractions(taskRecordService);
        Mockito.verify(channel).basicAck(1L, false);
    }

    @Test
    void handleNacksWhenTaskServiceFails() throws IOException {
        UUID taskId = UUID.randomUUID();
        Mockito.when(taskRecordService.markDeadLetter(Mockito.eq(taskId), Mockito.anyString(), Mockito.any()))
                .thenThrow(new IllegalStateException("database unavailable"));

        consumer.handle(message(taskId.toString(), "{}", "file.index"), channel);

        Mockito.verify(channel).basicNack(1L, false, false);
        Mockito.verify(channel, Mockito.never()).basicAck(Mockito.anyLong(), Mockito.anyBoolean());
    }

    private Message message(String taskIdHeader, String body, String routingKey) {
        MessageProperties properties = new MessageProperties();
        if (taskIdHeader != null) {
            properties.setHeader("taskId", taskIdHeader);
        }
        properties.setReceivedExchange("omni.task");
        properties.setReceivedRoutingKey(routingKey);
        properties.setDeliveryTag(1L);
        return new Message(body.getBytes(StandardCharsets.UTF_8), properties);
    }
}
