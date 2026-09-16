package com.omninest.worker.file;

import com.omninest.worker.runtime.ConditionalOnWorkerRuntime;

import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.file.event.FilePurgeRequestedEvent;
import com.omninest.modules.file.service.FilePurgeExecutionService;
import com.omninest.modules.file.service.FilePurgeRetryService;
import com.rabbitmq.client.Channel;
import java.io.IOException;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;

/**
 * 文件永久删除队列消费者。
 *
 * @author OmniNest
 */
@Slf4j
@Component
@RequiredArgsConstructor
@ConditionalOnWorkerRuntime
public class FilePurgeConsumer {
    private final FilePurgeExecutionService executionService;
    private final FilePurgeRetryService retryService;

    /**
     * 执行永久删除并在数据库状态落盘后确认消息。
     *
     * @param event 任务消息
     * @param message AMQP 消息
     * @param channel RabbitMQ 通道
     * @throws IOException ACK 或 NACK 失败时抛出
     */
    @RabbitListener(queues = QueueNames.FILE_PURGE_QUEUE)
    public void handle(FilePurgeRequestedEvent event, Message message, Channel channel) throws IOException {
        long deliveryTag = message.getMessageProperties().getDeliveryTag();
        try {
            executionService.execute(event);
            channel.basicAck(deliveryTag, false);
        } catch (Throwable executionException) {
            log.error("文件永久删除执行失败: taskId={}, errorType={}",
                    event.taskId(), executionException.getClass().getSimpleName(), executionException);
            try {
                retryService.handleFailure(event, executionException);
                channel.basicAck(deliveryTag, false);
            } catch (RuntimeException stateException) {
                log.error("文件永久删除失败状态写入失败，将重新投递原消息: taskId={}, errorType={}",
                        event.taskId(), stateException.getClass().getSimpleName(), stateException);
                channel.basicNack(deliveryTag, false, true);
            }
        }
    }
}
