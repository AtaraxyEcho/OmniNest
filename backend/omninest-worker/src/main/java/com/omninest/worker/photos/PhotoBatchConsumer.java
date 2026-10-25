package com.omninest.worker.photos;

import com.omninest.worker.runtime.ConditionalOnWorkerRuntime;

import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.photos.event.PhotoBatchEvent;
import com.omninest.modules.photos.service.PhotoBatchService;
import com.omninest.modules.task.service.TaskFailureRetryService;
import com.rabbitmq.client.Channel;
import java.io.IOException;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;

/**
 * 照片批量任务异步消费者，从队列接收批量任务并执行。
 */
@Slf4j
@Component
@RequiredArgsConstructor
@ConditionalOnWorkerRuntime
public class PhotoBatchConsumer {

    private final PhotoBatchService photoBatchService;
    private final TaskFailureRetryService taskFailureRetryService;

    @RabbitListener(queues = QueueNames.PHOTO_BATCH_QUEUE)
    public void handle(PhotoBatchEvent event, Message message, Channel channel) throws IOException {
        long deliveryTag = message.getMessageProperties().getDeliveryTag();
        try {
            log.info("收到照片批量任务: taskId={}, ownerUserId={}", event.taskId(), event.ownerUserId());
            photoBatchService.executeBatchTask(event.taskId(), event.ownerUserId());
            channel.basicAck(deliveryTag, false);
        } catch (Throwable e) {
            log.error("照片批量处理失败: taskId={}", event.taskId(), e);
            handleFailure(event, deliveryTag, channel, e);
        }
    }

    private void handleFailure(
            PhotoBatchEvent event,
            long deliveryTag,
            Channel channel,
            Throwable exception
    ) throws IOException {
        try {
            taskFailureRetryService.handleFailure(
                    event.taskId(), QueueNames.PHOTO_BATCH_ROUTING_KEY, event, exception);
            channel.basicAck(deliveryTag, false);
        } catch (RuntimeException stateException) {
            log.error("照片批量失败状态写入失败，将重新投递原消息: taskId={}, errorType={}",
                    event.taskId(), stateException.getClass().getSimpleName(), stateException);
            channel.basicNack(deliveryTag, false, true);
        }
    }
}
