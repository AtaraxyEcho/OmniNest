package com.omninest.worker.notification;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

import com.omninest.modules.notification.event.NotificationEmailRequestedEvent;
import com.omninest.modules.notification.service.NotificationEmailService;
import com.rabbitmq.client.Channel;
import java.io.IOException;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.core.MessageProperties;

/**
 * 邮件投递消费者的 ACK 与失败转移。
 *
 * @author OmniNest
 */
class NotificationEmailConsumerTest {

    private static final UUID TASK_ID = UUID.fromString("80000000-0000-0000-0000-000000000001");
    private static final UUID USER_ID = UUID.fromString("80000000-0000-0000-0000-000000000002");
    private static final UUID NOTIFICATION_ID = UUID.fromString("80000000-0000-0000-0000-000000000003");

    private final NotificationEmailService deliveryService = mock(NotificationEmailService.class);
    private final NotificationEmailRetryService retryService = mock(NotificationEmailRetryService.class);
    private final Channel channel = mock(Channel.class);
    private final NotificationEmailConsumer consumer =
            new NotificationEmailConsumer(deliveryService, retryService);

    @Test
    void successAcksWithoutTouchingRetry() throws IOException {
        NotificationEmailRequestedEvent event = event();

        consumer.handle(event, message(), channel);

        verify(deliveryService).deliver(event);
        verify(channel).basicAck(1L, false);
        verifyNoRetry();
    }

    @Test
    void deliveryFailureHandsOverToRetryAndAcks() throws IOException {
        NotificationEmailRequestedEvent event = event();
        RuntimeException failure = new RuntimeException("smtp timeout");
        doThrow(failure).when(deliveryService).deliver(event);

        consumer.handle(event, message(), channel);

        verify(retryService).handleFailure(event, failure);
        verify(channel).basicAck(1L, false);
    }

    @Test
    void retryStateWriteFailureRoutesToDeadLetterQueue() throws IOException {
        NotificationEmailRequestedEvent event = event();
        doThrow(new RuntimeException("db down")).when(deliveryService).deliver(event);
        doThrow(new IllegalStateException("retry row locked"))
                .when(retryService).handleFailure(eq(event), any(Throwable.class));

        consumer.handle(event, message(), channel);

        verify(channel, never()).basicAck(anyLong(), eq(false));
        verify(channel).basicNack(1L, false, false);
    }

    private void verifyNoRetry() {
        verify(retryService, never()).handleFailure(any(), any());
    }

    private NotificationEmailRequestedEvent event() {
        return new NotificationEmailRequestedEvent(TASK_ID, USER_ID, NOTIFICATION_ID);
    }

    private Message message() {
        MessageProperties properties = new MessageProperties();
        properties.setDeliveryTag(1L);
        return new Message(new byte[0], properties);
    }
}
