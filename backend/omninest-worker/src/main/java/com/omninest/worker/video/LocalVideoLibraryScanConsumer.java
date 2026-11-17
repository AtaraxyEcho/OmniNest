package com.omninest.worker.video;

import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.video.event.LocalVideoLibraryScanRequestedEvent;
import com.omninest.modules.video.service.VideoLibraryScanRetryService;
import com.omninest.modules.video.service.VideoLibrarySourceService;
import com.omninest.worker.runtime.ConditionalOnWorkerRuntime;
import com.rabbitmq.client.Channel;
import java.io.IOException;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;

/**
 * 本地影视库扫描任务消费者。
 *
 * @author OmniNest
 */
@Slf4j
@Component
@RequiredArgsConstructor
@ConditionalOnWorkerRuntime
public class LocalVideoLibraryScanConsumer {

    private final VideoLibrarySourceService sourceService;
    private final VideoLibraryScanRetryService retryService;

    /**
     * 执行本地影视库扫描消息并确认消费结果。
     *
     * @param event 扫描请求事件
     * @param message RabbitMQ 消息
     * @param channel RabbitMQ 通道
     * @throws IOException 消息确认失败时抛出
     */
    @RabbitListener(
            queues = QueueNames.LOCAL_VIDEO_LIBRARY_SCAN_QUEUE,
            containerFactory = "localMediaTaskListenerContainerFactory"
    )
    public void handle(
            LocalVideoLibraryScanRequestedEvent event,
            Message message,
            Channel channel
    ) throws IOException {
        long deliveryTag = message.getMessageProperties().getDeliveryTag();
        try {
            log.info("收到本地影视库扫描任务: taskId={}, sourceId={}", event.taskId(), event.sourceId());
            sourceService.executeScan(event);
            channel.basicAck(deliveryTag, false);
        } catch (Throwable e) {
            try {
                retryService.handleFailure(event, e);
                channel.basicAck(deliveryTag, false);
            } catch (RuntimeException retryException) {
                log.error("本地影视库扫描失败状态持久化异常: taskId={}", event.taskId(), retryException);
                channel.basicNack(deliveryTag, false, false);
            }
        }
    }
}
