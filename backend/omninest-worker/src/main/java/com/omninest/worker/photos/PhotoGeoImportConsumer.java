package com.omninest.worker.photos;

import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.photos.event.PhotoGeoImportEvent;
import com.omninest.modules.photos.service.GeonamesImportService;
import com.omninest.worker.runtime.ConditionalOnWorkerRuntime;
import com.rabbitmq.client.Channel;
import java.io.IOException;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;

/**
 * GeoNames 数据集导入任务消费者。
 * 执行成功或失败裁决完成后确认消息；延迟重投由任务 Outbox 负责。
 *
 * @author OmniNest
 */
@Slf4j
@Component
@RequiredArgsConstructor
@ConditionalOnWorkerRuntime
public class PhotoGeoImportConsumer {

    private final GeonamesImportService geonamesImportService;
    private final PhotoGeoImportRetryService retryService;

    /**
     * 执行 GeoNames 导入任务并确认消息结果。
     *
     * @param event 导入任务事件
     * @param message AMQP 消息
     * @param channel RabbitMQ 通道
     * @throws IOException ACK 或 NACK 失败时抛出
     */
    @RabbitListener(queues = QueueNames.PHOTO_GEO_IMPORT_QUEUE)
    public void handle(PhotoGeoImportEvent event, Message message, Channel channel) throws IOException {
        long deliveryTag = message.getMessageProperties().getDeliveryTag();
        try {
            log.info("收到 GeoNames 导入任务: taskId={}, datasetVersion={}, dumpDate={}",
                    event.taskId(), event.datasetVersion(), event.dumpDate());
            geonamesImportService.executeImportTask(event.taskId());
            channel.basicAck(deliveryTag, false);
        } catch (Throwable e) {
            log.error("GeoNames 导入任务失败: taskId={}, datasetVersion={}", event.taskId(), event.datasetVersion(), e);
            try {
                retryService.handleImportFailure(event, e);
                channel.basicAck(deliveryTag, false);
            } catch (RuntimeException retryException) {
                log.error("GeoNames 导入任务失败状态写入失败，将重新投递原消息: taskId={}",
                        event.taskId(), retryException);
                channel.basicNack(deliveryTag, false, true);
            }
        }
    }
}
