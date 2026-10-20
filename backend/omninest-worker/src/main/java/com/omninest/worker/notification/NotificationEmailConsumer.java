package com.omninest.worker.notification;

import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.notification.event.NotificationEmailRequestedEvent;
import com.omninest.modules.notification.service.NotificationEmailService;
import com.omninest.worker.runtime.ConditionalOnWorkerRuntime;
import com.rabbitmq.client.Channel;
import java.io.IOException;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;

/**
 * 通知邮件投递队列消费者。
 *
 * @author OmniNest
 */
@Slf4j
@Component
@RequiredArgsConstructor
@ConditionalOnWorkerRuntime
public class NotificationEmailConsumer {

    private final NotificationEmailService notificationEmailService;
    private final NotificationEmailRetryService retryService;

    /**
     * 投递邮件并在状态落盘后确认消息。
     *
     * @param event 任务消息
     * @param message AMQP 消息
     * @param channel RabbitMQ 通道
     * @throws IOException ACK 或 NACK 失败时抛出
     */
    @RabbitListener(queues = QueueNames.NOTIFICATION_EMAIL_QUEUE)
    public void handle(NotificationEmailRequestedEvent event, Message message, Channel channel) throws IOException {
        long deliveryTag = message.getMessageProperties().getDeliveryTag();
        try {
            notificationEmailService.deliver(event);
            channel.basicAck(deliveryTag, false);
        } catch (Throwable exception) {
            handleFailure(event, exception, deliveryTag, channel);
        }
    }

    private void handleFailure(
            NotificationEmailRequestedEvent event,
            Throwable exception,
            long deliveryTag,
            Channel channel
    ) throws IOException {
        try {
            retryService.handleFailure(event, exception);
            channel.basicAck(deliveryTag, false);
        } catch (RuntimeException stateException) {
            log.error("邮件投递失败状态写入异常，将重新投递原消息: taskId={}, errorType={}",
                    event.taskId(), stateException.getClass().getSimpleName(), stateException);
            channel.basicNack(deliveryTag, false, true);
        }
    }
}
