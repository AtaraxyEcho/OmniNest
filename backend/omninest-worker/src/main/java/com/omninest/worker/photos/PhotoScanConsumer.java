package com.omninest.worker.photos;

import com.omninest.worker.runtime.ConditionalOnWorkerRuntime;

import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.photos.event.PhotoScanEvent;
import com.omninest.modules.photos.service.PhotoAdminService;
import com.rabbitmq.client.Channel;
import java.io.IOException;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;

/**
 * 照片扫描异步消费者，从队列接收扫描任务并执行导入。
 */
@Slf4j
@Component
@RequiredArgsConstructor
@ConditionalOnWorkerRuntime
public class PhotoScanConsumer {

    private final PhotoAdminService photoAdminService;

    @RabbitListener(queues = QueueNames.PHOTO_SCAN_QUEUE)
    public void handle(PhotoScanEvent event, Message message, Channel channel) throws IOException {
        long deliveryTag = message.getMessageProperties().getDeliveryTag();
        try {
            log.info("收到照片扫描任务: jobId={}, ownerUserId={}", event.jobId(), event.ownerUserId());
            photoAdminService.executeScanJob(event.jobId(), event.ownerUserId());
            channel.basicAck(deliveryTag, false);
        } catch (Throwable e) {
            log.error("照片扫描处理失败: jobId={}", event.jobId(), e);
            channel.basicNack(deliveryTag, false, false);
        }
    }
}
