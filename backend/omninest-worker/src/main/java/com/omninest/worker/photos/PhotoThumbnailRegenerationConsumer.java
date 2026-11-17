package com.omninest.worker.photos;

import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.photos.event.PhotoThumbnailRegenerationEvent;
import com.omninest.modules.photos.service.PhotoAdminService;
import com.omninest.modules.task.service.TaskFailureRetryService;
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
    private final TaskFailureRetryService taskFailureRetryService;

    @RabbitListener(queues = QueueNames.PHOTO_THUMBNAILS_QUEUE)
    public void handle(PhotoThumbnailRegenerationEvent event, Message message, Channel channel) throws IOException {
        long deliveryTag = message.getMessageProperties().getDeliveryTag();
        try {
            log.info("收到缩略图重生成任务: taskId={}, ownerUserId={}", event.taskId(), event.ownerUserId());
            photoAdminService.executeThumbnailRegeneration(event.taskId(), event.ownerUserId());
            channel.basicAck(deliveryTag, false);
        } catch (Throwable e) {
            // 事件自带 taskId 且任务行已存在：接统一失败裁决即可白拿 1m/5m/15m 退避重试，
            // 不再把瞬时故障一次性打进死信。
            log.error("缩略图重生成处理失败: taskId={}", event.taskId(), e);
            try {
                taskFailureRetryService.handleFailure(
                        event.taskId(), QueueNames.PHOTO_THUMBNAILS_ROUTING_KEY, event,
                        e instanceof Exception exception ? exception : new IllegalStateException(e));
                channel.basicAck(deliveryTag, false);
            } catch (RuntimeException stateException) {
                log.error("缩略图重生成失败状态写入失败，转入死信队列: taskId={}", event.taskId());
                channel.basicNack(deliveryTag, false, false);
            }
        }
    }
}
