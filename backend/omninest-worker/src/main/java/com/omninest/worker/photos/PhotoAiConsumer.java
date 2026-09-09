package com.omninest.worker.photos;

import com.omninest.worker.runtime.ConditionalOnWorkerRuntime;

import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.photos.event.PhotoAiEvent;
import com.omninest.modules.photos.service.PhotoAiTaskService;
import com.rabbitmq.client.Channel;
import java.io.IOException;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;

/**
 * 照片 AI 异步任务消费者。
 * 执行成功或失败裁决完成后确认消息；延迟重投由任务 Outbox 负责。
 *
 * @author OmniNest
 */
@Slf4j
@Component
@RequiredArgsConstructor
@ConditionalOnWorkerRuntime
public class PhotoAiConsumer {

    private final PhotoAiTaskService photoAiTaskService;
    private final PhotoAiTaskRetryService retryService;

    /**
     * 执行照片 AI 任务并确认消息结果。
     *
     * @param event 照片 AI 任务事件
     * @param message AMQP 消息
     * @param channel RabbitMQ 通道
     * @throws IOException ACK 或 NACK 失败时抛出
     */
    @RabbitListener(queues = QueueNames.PHOTO_AI_QUEUE)
    public void handle(PhotoAiEvent event, Message message, Channel channel) throws IOException {
        long deliveryTag = message.getMessageProperties().getDeliveryTag();
        try {
            log.info(
                    "收到照片 AI 任务: taskId={}, photoId={}, ownerUserId={}, mode={}",
                    event.taskId(),
                    event.photoId(),
                    event.ownerUserId(),
                    event.mode()
            );
            photoAiTaskService.execute(event);
            channel.basicAck(deliveryTag, false);
        } catch (RuntimeException e) {
            if (retryService.isDependencyNotReady(e)) {
                log.warn(
                        "照片 AI 任务依赖未就绪，等待重试: taskId={}, photoId={}, error={}",
                        event.taskId(),
                        event.photoId(),
                        e.getMessage()
                );
            } else {
                log.error("照片 AI 任务失败: taskId={}, photoId={}", event.taskId(), event.photoId(), e);
            }
            try {
                retryService.handlePhotoAiFailure(event, e);
                channel.basicAck(deliveryTag, false);
            } catch (RuntimeException retryException) {
                log.error("照片 AI 任务失败状态写入失败，将重新投递原消息: taskId={}",
                        event.taskId(), retryException);
                channel.basicNack(deliveryTag, false, true);
            }
        }
    }
}
