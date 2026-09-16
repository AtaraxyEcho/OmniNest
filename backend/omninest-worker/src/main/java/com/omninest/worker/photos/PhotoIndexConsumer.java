package com.omninest.worker.photos;

import com.omninest.worker.runtime.ConditionalOnWorkerRuntime;

import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.photos.event.PhotoIndexEvent;
import com.omninest.modules.photos.service.PhotoIndexTaskService;
import com.rabbitmq.client.Channel;
import java.io.IOException;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;

/**
 * 照片索引异步消费者。
 *
 * @author OmniNest
 */
@Slf4j
@Component
@RequiredArgsConstructor
@ConditionalOnWorkerRuntime
public class PhotoIndexConsumer {

    private final PhotoIndexTaskService taskService;

    /**
     * 处理照片索引消息并确认消费结果。
     *
     * @param event 照片索引事件
     * @param message AMQP 消息
     * @param channel RabbitMQ 通道
     * @throws IOException ACK 或 NACK 失败时抛出
     */
    @RabbitListener(queues = QueueNames.PHOTO_INDEX_QUEUE)
    public void handle(PhotoIndexEvent event, Message message, Channel channel) throws IOException {
        long deliveryTag = message.getMessageProperties().getDeliveryTag();
        try {
            log.info("收到照片索引任务: photoId={}, ownerUserId={}", event.photoId(), event.ownerUserId());
            if (!taskService.index(event.ownerUserId(), event.photoId())) {
                log.warn("照片不存在，跳过索引: photoId={}", event.photoId());
                channel.basicAck(deliveryTag, false);
                return;
            }
            channel.basicAck(deliveryTag, false);
        } catch (Throwable e) {
            log.error("照片索引处理失败: photoId={}", event.photoId(), e);
            channel.basicNack(deliveryTag, false, false);
        }
    }
}
