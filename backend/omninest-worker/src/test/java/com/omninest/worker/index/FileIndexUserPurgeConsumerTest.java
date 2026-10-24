package com.omninest.worker.index;

import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.modules.search.event.FileIndexUserPurgeEvent;
import com.omninest.modules.search.service.SearchIndexUserPurgeService;
import com.rabbitmq.client.Channel;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.core.MessageProperties;

/**
 * 用户索引目录清理消费者的短重试与确认语义。
 */
class FileIndexUserPurgeConsumerTest {

    private static final UUID USER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");

    private final SearchIndexUserPurgeService purgeService = mock(SearchIndexUserPurgeService.class);
    private final FileIndexUserPurgeConsumer consumer = new FileIndexUserPurgeConsumer(purgeService);

    @Test
    void retriesTransientDeleteFailuresBeforeAcking() throws Exception {
        Channel channel = mock(Channel.class);
        Message message = messageWithDeliveryTag(7L);
        when(purgeService.purgePhysicalIndex(USER_ID)).thenReturn(false, false, true);

        consumer.handle(new FileIndexUserPurgeEvent(USER_ID), message, channel);

        verify(purgeService, times(3)).purgePhysicalIndex(USER_ID);
        verify(channel).basicAck(7L, false);
    }

    @Test
    void sendsToDeadLetterAfterRetriesExhausted() throws Exception {
        Channel channel = mock(Channel.class);
        Message message = messageWithDeliveryTag(8L);
        when(purgeService.purgePhysicalIndex(USER_ID)).thenReturn(false);

        consumer.handle(new FileIndexUserPurgeEvent(USER_ID), message, channel);

        verify(purgeService, times(3)).purgePhysicalIndex(USER_ID);
        verify(channel).basicNack(8L, false, false);
    }

    private Message messageWithDeliveryTag(long deliveryTag) {
        Message message = mock(Message.class);
        MessageProperties properties = mock(MessageProperties.class);
        when(message.getMessageProperties()).thenReturn(properties);
        when(properties.getDeliveryTag()).thenReturn(deliveryTag);
        return message;
    }
}
