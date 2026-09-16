package com.omninest.worker.media;

import com.omninest.worker.runtime.ConditionalOnWorkerRuntime;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.file.event.MediaAutoImportRequestedEvent;
import com.omninest.modules.task.service.TaskRecordService;
import com.rabbitmq.client.Channel;
import java.io.IOException;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;

/**
 * 媒体自动导入队列消费者。
 *
 * @author OmniNest
 */
@Slf4j
@Component
@RequiredArgsConstructor
@ConditionalOnWorkerRuntime
public class MediaAutoImportConsumer {
    private final MediaAutoImportExecutionService executionService;
    private final MediaAutoImportRetryService retryService;
    private final TaskRecordService taskRecordService;

    /**
     * 执行媒体自动导入并在状态落盘后确认消息。
     *
     * @param event 任务消息
     * @param message AMQP 消息
     * @param channel RabbitMQ 通道
     * @throws IOException ACK 或 NACK 失败时抛出
     */
    @RabbitListener(queues = QueueNames.MEDIA_AUTO_IMPORT_QUEUE)
    public void handle(MediaAutoImportRequestedEvent event, Message message, Channel channel) throws IOException {
        long deliveryTag = message.getMessageProperties().getDeliveryTag();
        try {
            executionService.execute(event);
            channel.basicAck(deliveryTag, false);
        } catch (BusinessException exception) {
            if (ErrorCode.FILE_NOT_FOUND.equals(exception.errorCode())
                    || ErrorCode.FILE_LIFECYCLE_CONFLICT.equals(exception.errorCode())) {
                taskRecordService.markCancelled(event.taskId());
                log.info("媒体源文件已删除或正在永久删除，取消自动导入: taskId={}, fileNodeId={}",
                        event.taskId(), event.file().fileNodeId());
                channel.basicAck(deliveryTag, false);
                return;
            }
            handleFailure(event, exception, deliveryTag, channel);
        } catch (Throwable exception) {
            handleFailure(event, exception, deliveryTag, channel);
        }
    }

    private void handleFailure(
            MediaAutoImportRequestedEvent event,
            Throwable exception,
            long deliveryTag,
            Channel channel
    ) throws IOException {
        try {
            retryService.handleFailure(event, exception);
            channel.basicAck(deliveryTag, false);
        } catch (RuntimeException stateException) {
            log.error("媒体自动导入失败状态写入失败，将重新投递原消息: taskId={}, errorType={}",
                    event.taskId(), stateException.getClass().getSimpleName(), stateException);
            channel.basicNack(deliveryTag, false, true);
        }
    }
}
