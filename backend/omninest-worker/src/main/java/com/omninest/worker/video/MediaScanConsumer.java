package com.omninest.worker.video;

import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.video.event.MediaLibraryScanRequestedEvent;
import com.omninest.modules.video.service.MediaScanRetryService;
import com.omninest.modules.video.service.MovieTaskService;
import com.omninest.worker.runtime.ConditionalOnWorkerRuntime;
import com.rabbitmq.client.Channel;
import java.io.IOException;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;

/**
 * 用户媒体库扫描任务消费者。
 *
 * @author OmniNest
 */
@Slf4j
@Component
@RequiredArgsConstructor
@ConditionalOnWorkerRuntime
public class MediaScanConsumer {

    private final MovieTaskService movieTaskService;
    private final MediaScanRetryService retryService;

    /**
     * 执行媒体库扫描消息并确认消费结果。
     *
     * @param event 扫描请求事件
     * @param message RabbitMQ 消息
     * @param channel RabbitMQ 通道
     * @throws IOException 消息确认失败时抛出
     */
    @RabbitListener(queues = QueueNames.MEDIA_SCAN_QUEUE)
    public void handle(
            MediaLibraryScanRequestedEvent event,
            Message message,
            Channel channel
    ) throws IOException {
        long deliveryTag = message.getMessageProperties().getDeliveryTag();
        try {
            log.info("收到媒体库扫描任务: taskId={}, rootFolderId={}", event.taskId(), event.rootFolderId());
            movieTaskService.executeScan(event);
            channel.basicAck(deliveryTag, false);
        } catch (Throwable e) {
            try {
                retryService.handleFailure(event, e);
                channel.basicAck(deliveryTag, false);
            } catch (RuntimeException retryException) {
                log.error("媒体库扫描失败状态持久化异常: taskId={}", event.taskId(), retryException);
                channel.basicNack(deliveryTag, false, false);
            }
        }
    }
}
