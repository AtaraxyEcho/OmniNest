package com.omninest.worker.photos;

import com.omninest.modules.photos.event.PhotoIndexEvent;
import com.omninest.modules.photos.service.PhotoIndexTaskService;
import com.rabbitmq.client.Channel;
import java.io.IOException;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.core.MessageProperties;

/**
 * 照片索引消费者消息编排测试。
 *
 * @author OmniNest
 */
class PhotoIndexConsumerTest {
    private final PhotoIndexTaskService taskService = Mockito.mock(PhotoIndexTaskService.class);
    private final Channel channel = Mockito.mock(Channel.class);
    private final PhotoIndexConsumer consumer = new PhotoIndexConsumer(taskService);

    @Test
    void handleAcknowledgesIndexedPhoto() throws IOException {
        PhotoIndexEvent event = event();
        Mockito.when(taskService.index(event.ownerUserId(), event.photoId())).thenReturn(true);

        consumer.handle(event, message(), channel);

        Mockito.verify(taskService).index(event.ownerUserId(), event.photoId());
        Mockito.verify(channel).basicAck(1L, false);
    }

    @Test
    void handleAcknowledgesMissingPhoto() throws IOException {
        PhotoIndexEvent event = event();
        Mockito.when(taskService.index(event.ownerUserId(), event.photoId())).thenReturn(false);

        consumer.handle(event, message(), channel);

        Mockito.verify(channel).basicAck(1L, false);
    }

    @Test
    void handleRetriesTransientFailureBeforeAcknowledging() throws IOException {
        PhotoIndexEvent event = event();
        Mockito.when(taskService.index(event.ownerUserId(), event.photoId()))
                .thenThrow(new IllegalStateException("index lock"))
                .thenReturn(true);

        consumer.handle(event, message(), channel);

        Mockito.verify(taskService, Mockito.times(2)).index(event.ownerUserId(), event.photoId());
        Mockito.verify(channel).basicAck(1L, false);
        Mockito.verify(channel, Mockito.never()).basicNack(
                Mockito.anyLong(), Mockito.anyBoolean(), Mockito.anyBoolean());
    }

    @Test
    void handleNacksWhenIndexingFails() throws IOException {
        PhotoIndexEvent event = event();
        Mockito.when(taskService.index(event.ownerUserId(), event.photoId()))
                .thenThrow(new IllegalStateException("index unavailable"));

        consumer.handle(event, message(), channel);

        Mockito.verify(channel).basicNack(1L, false, false);
        Mockito.verify(channel, Mockito.never()).basicAck(Mockito.anyLong(), Mockito.anyBoolean());
    }

    private PhotoIndexEvent event() {
        return new PhotoIndexEvent(UUID.randomUUID(), UUID.randomUUID());
    }

    private Message message() {
        MessageProperties properties = new MessageProperties();
        properties.setDeliveryTag(1L);
        return new Message(new byte[0], properties);
    }
}
