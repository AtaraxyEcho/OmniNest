package com.omninest.worker.photos;

import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.photos.event.PhotoMotionRescanEvent;
import com.omninest.modules.photos.service.PhotoMotionRescanService;
import com.omninest.worker.runtime.ConditionalOnWorkerRuntime;
import com.rabbitmq.client.Channel;
import java.io.IOException;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;

/**
 * 动态照片存量回扫任务消费者。
 * 执行成功或失败裁决完成后确认消息；延迟重投由任务 Outbox 负责。
 *
 * @author OmniNest
 */
@Slf4j
@Component
@RequiredArgsConstructor
@ConditionalOnWorkerRuntime
public class PhotoMotionRescanConsumer {

    private final PhotoMotionRescanService photoMotionRescanService;

    /**
     * 执行动态照片回扫任务并确认消息结果。
     *
     * @param event 回扫任务事件
     * @param message AMQP 消息
     * @param channel RabbitMQ 通道
     * @throws IOException ACK 失败时抛出
     */
    @RabbitListener(queues = QueueNames.PHOTO_MOTION_RESCAN_QUEUE)
    public void handle(PhotoMotionRescanEvent event, Message message, Channel channel) throws IOException {
        long deliveryTag = message.getMessageProperties().getDeliveryTag();
        try {
            log.info("收到动态照片回扫任务: taskId={}, ownerUserId={}", event.taskId(), event.ownerUserId());
            photoMotionRescanService.executeRescanTask(event.taskId());
            channel.basicAck(deliveryTag, false);
        } catch (Throwable e) {
            log.error("动态照片回扫任务执行异常: taskId={}", event.taskId(), e);
            channel.basicAck(deliveryTag, false);
        }
    }
}
