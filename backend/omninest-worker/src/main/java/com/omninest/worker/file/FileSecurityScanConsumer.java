package com.omninest.worker.file;

import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.file.event.FileSecurityScanRequestedEvent;
import com.omninest.modules.file.service.FileIngressPromotionService;
import com.omninest.modules.file.service.FileIngressScanRetryService;
import com.omninest.modules.task.service.TaskRecordService;
import com.omninest.worker.runtime.ConditionalOnWorkerRuntime;
import com.rabbitmq.client.Channel;
import java.io.IOException;
import java.util.Map;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;

/**
 * 文件安全扫描队列消费者：认领任务后执行扫描晋升，失败交由重试服务协调。
 *
 * @author OmniNest
 */
@Slf4j
@Component
@RequiredArgsConstructor
@ConditionalOnWorkerRuntime
public class FileSecurityScanConsumer {
    private final TaskRecordService taskRecordService;
    private final FileIngressPromotionService promotionService;
    private final FileIngressScanRetryService retryService;

    /**
     * 执行安全扫描与晋升并在数据库状态落盘后确认消息。
     *
     * @param event 任务消息
     * @param message AMQP 消息
     * @param channel RabbitMQ 通道
     * @throws IOException ACK 或 NACK 失败时抛出
     */
    @RabbitListener(queues = QueueNames.FILE_SECURITY_SCAN_QUEUE)
    public void handle(FileSecurityScanRequestedEvent event, Message message, Channel channel) throws IOException {
        long deliveryTag = message.getMessageProperties().getDeliveryTag();
        try {
            if (!taskRecordService.claimForExecution(event.taskId(), "SCANNING")) {
                log.info("安全扫描任务已被其他执行者领取或到达终态，跳过: taskId={}", event.taskId());
                channel.basicAck(deliveryTag, false);
                return;
            }
            taskRecordService.markRunning(event.taskId(), "SCANNING");
            FileIngressPromotionService.PromotionOutcome outcome = promotionService.process(event);
            Map<String, Object> result = new java.util.LinkedHashMap<>();
            result.put("ingressItemId", event.ingressItemId().toString());
            if (outcome.fileNodeId() != null) {
                result.put("fileNodeId", outcome.fileNodeId().toString());
            }
            if (outcome.mediaAutoImportTaskId() != null) {
                result.put("mediaAutoImportTaskId", outcome.mediaAutoImportTaskId().toString());
            }
            taskRecordService.markCompleted(event.taskId(), result);
            channel.basicAck(deliveryTag, false);
        } catch (Throwable executionException) {
            log.error("文件安全扫描执行失败: taskId={}, errorType={}",
                    event.taskId(), executionException.getClass().getSimpleName(), executionException);
            try {
                retryService.handleFailure(event, executionException);
                channel.basicAck(deliveryTag, false);
            } catch (RuntimeException stateException) {
                log.error("文件安全扫描失败状态写入失败，将重新投递原消息: taskId={}, errorType={}",
                        event.taskId(), stateException.getClass().getSimpleName(), stateException);
                channel.basicNack(deliveryTag, false, true);
            }
        }
    }
}
