package com.omninest.worker.external;

import com.omninest.worker.runtime.ConditionalOnWorkerRuntime;

import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.file.event.ExternalImportRequestedEvent;
import com.omninest.modules.file.service.ExternalImportExecutionService;
import com.omninest.modules.file.service.ExternalImportRetryService;
import com.rabbitmq.client.Channel;
import java.io.IOException;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;

/**
 * 外部存储导入消费者。
 * <p>
 * 监听外部存储导入任务队列，委托 ExternalImportExecutionService 执行。
 */
@Slf4j
@Component
@RequiredArgsConstructor
@ConditionalOnWorkerRuntime
public class ExternalImportConsumer {
    private final ExternalImportExecutionService executionService;
    private final ExternalImportRetryService retryService;

    @RabbitListener(queues = QueueNames.EXTERNAL_IMPORT_QUEUE)
    public void onExternalImportRequested(ExternalImportRequestedEvent event, Message message, Channel channel) throws IOException {
        long deliveryTag = message.getMessageProperties().getDeliveryTag();
        try {
            log.info("收到外部存储导入任务: taskId={}", event.taskId());
            executionService.execute(event);
            channel.basicAck(deliveryTag, false);
        } catch (Throwable e) {
            try {
                // 与媒体库扫描同口径：瞬时故障按 1/5/15 分钟经 Outbox 延迟重投，
                // 业务错误判终态，重试耗尽才进死信。直接 nack 会让导入没有第二次机会。
                retryService.handleFailure(event, e);
                channel.basicAck(deliveryTag, false);
            } catch (RuntimeException retryException) {
                log.error("外部存储导入失败状态持久化异常: taskId={}", event.taskId(), retryException);
                channel.basicNack(deliveryTag, false, false);
            }
        }
    }
}
