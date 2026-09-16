package com.omninest.worker.photos;

import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.photos.event.PhotoThumbnailRegenerationEvent;
import com.omninest.modules.photos.service.PhotoAdminService;
import com.omninest.worker.runtime.ConditionalOnWorkerRuntime;
import com.rabbitmq.client.Channel;
import java.io.IOException;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;

/**
 * 照片缩略图重生成异步消费者，从队列接收任务并逐张补齐缺失缩略图。
 */
@Slf4j
@Component
@RequiredArgsConstructor
@ConditionalOnWorkerRuntime
public class PhotoThumbnailRegenerationConsumer {

    private final PhotoAdminService photoAdminService;

    @RabbitListener(queues = QueueNames.PHOTO_THUMBNAILS_QUEUE)
    public void handle(PhotoThumbnailRegenerationEvent event, Message message, Channel channel) throws IOException {
        long deliveryTag = message.getMessageProperties().getDeliveryTag();
        try {
            log.info("收到缩略图重生成任务: taskId={}, ownerUserId={}", event.taskId(), event.ownerUserId());
            photoAdminService.executeThumbnailRegeneration(event.taskId(), event.ownerUserId());
            channel.basicAck(deliveryTag, false);
        } catch (Throwable e) {
            log.error("缩略图重生成处理失败: taskId={}", event.taskId(), e);
            channel.basicNack(deliveryTag, false, false);
        }
    }
}
