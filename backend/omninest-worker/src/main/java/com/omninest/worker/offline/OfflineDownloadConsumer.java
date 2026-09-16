package com.omninest.worker.offline;

import com.omninest.worker.runtime.ConditionalOnWorkerRuntime;

import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.file.event.OfflineDownloadRequestedEvent;
import com.omninest.modules.file.service.OfflineDownloadExecutionService;
import com.rabbitmq.client.Channel;
import java.io.IOException;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;

@Slf4j
@Component
@RequiredArgsConstructor
@ConditionalOnWorkerRuntime
public class OfflineDownloadConsumer {
    private final OfflineDownloadExecutionService executionService;

    @RabbitListener(queues = QueueNames.OFFLINE_DOWNLOAD_QUEUE)
    public void handle(OfflineDownloadRequestedEvent event, Message message, Channel channel) throws IOException {
        long deliveryTag = message.getMessageProperties().getDeliveryTag();
        try {
            log.info("收到离线下载任务: taskId={}", event.taskId());
            executionService.execute(event);
            channel.basicAck(deliveryTag, false);
        } catch (Throwable e) {
            log.error("离线下载处理失败: taskId={}", event.taskId(), e);
            channel.basicNack(deliveryTag, false, false);
        }
    }
}
