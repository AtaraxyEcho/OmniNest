package com.omninest.worker.reader;

import com.omninest.modules.reader.event.ComicParseTaskEvent;
import com.omninest.modules.reader.service.ComicParseTaskService;
import com.rabbitmq.client.Channel;
import java.io.IOException;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.Mockito;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.core.MessageProperties;

/**
 * 漫画解析消费者单元测试，验证消息确认与死信编排。
 *
 * @author OmniNest
 */
@ExtendWith(MockitoExtension.class)
class ComicParseConsumerTest {

    private static final UUID TASK_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000002");
    private static final UUID ITEM_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");
    private static final UUID SOURCE_ID = UUID.fromString("30000000-0000-0000-0000-000000000001");
    private static final UUID FILE_NODE_ID = UUID.fromString("40000000-0000-0000-0000-000000000001");
    private static final long DELIVERY_TAG = 7L;

    @Mock
    private ComicParseTaskService taskService;

    @Mock
    private Channel channel;

    @Mock
    private ComicParseRetryService retryService;

    @InjectMocks
    private ComicParseConsumer consumer;

    @Test
    void handleAcknowledgesCompletedUseCase() throws IOException {
        ComicParseTaskEvent event = event();

        consumer.handle(event, message(), channel);

        Mockito.verify(taskService).process(event);
        Mockito.verify(channel).basicAck(DELIVERY_TAG, false);
        Mockito.verify(channel, Mockito.never()).basicNack(DELIVERY_TAG, false, false);
    }

    @Test
    void handleSchedulesRetryAndAcknowledgesUseCaseFailure() throws IOException {
        ComicParseTaskEvent event = event();
        Mockito.doThrow(new IllegalStateException("database unavailable"))
                .when(taskService)
                .process(event);

        consumer.handle(event, message(), channel);

        Mockito.verify(retryService).handleFailure(Mockito.eq(event), Mockito.any(IllegalStateException.class));
        Mockito.verify(channel).basicAck(DELIVERY_TAG, false);
        Mockito.verify(channel, Mockito.never()).basicNack(DELIVERY_TAG, false, false);
    }

    @Test
    void handleSendsMessageToDeadLetterWhenRetryPersistenceFails() throws IOException {
        ComicParseTaskEvent event = event();
        IllegalStateException failure = new IllegalStateException("database unavailable");
        Mockito.doThrow(failure).when(taskService).process(event);
        Mockito.doThrow(new IllegalStateException("retry unavailable"))
                .when(retryService)
                .handleFailure(event, failure);

        consumer.handle(event, message(), channel);

        Mockito.verify(channel).basicNack(DELIVERY_TAG, false, false);
        Mockito.verify(channel, Mockito.never()).basicAck(DELIVERY_TAG, false);
    }

    private ComicParseTaskEvent event() {
        return new ComicParseTaskEvent(
                TASK_ID,
                OWNER_ID,
                ITEM_ID,
                SOURCE_ID,
                FILE_NODE_ID,
                "CBZ",
                "hash",
                false);
    }

    private Message message() {
        MessageProperties properties = new MessageProperties();
        properties.setDeliveryTag(DELIVERY_TAG);
        return new Message(new byte[0], properties);
    }
}
