package com.omninest.worker.index;

import com.omninest.worker.runtime.ConditionalOnWorkerRuntime;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.file.event.FileRestoredEvent;
import com.rabbitmq.client.Channel;
import java.io.IOException;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;

/**
 * 文件恢复索引消费者，只恢复搜索索引，不重复执行上传后的媒体导入流程。
 *
 * @author OmniNest
 */
@Slf4j
@Component
@RequiredArgsConstructor
@ConditionalOnWorkerRuntime
public class FileRestoreIndexConsumer {
    private final FileIndexTaskService taskService;
    private final FileRestoreDerivedAssetService derivedAssetService;

    /**
     * 处理文件恢复索引消息。
     *
     * @param event 文件恢复事件
     * @param message AMQP 消息
     * @param channel RabbitMQ 通道
     * @throws IOException ACK 或 NACK 失败时抛出
     */
    @RabbitListener(queues = QueueNames.FILE_RESTORE_INDEX_QUEUE)
    public void handle(FileRestoredEvent event, Message message, Channel channel) throws IOException {
        long deliveryTag = message.getMessageProperties().getDeliveryTag();
        try {
            derivedAssetService.validateAndRepair(event);
            taskService.processRestored(event);
            channel.basicAck(deliveryTag, false);
        } catch (BusinessException exception) {
            if (ErrorCode.FILE_NOT_FOUND.equals(exception.errorCode())
                    || ErrorCode.FILE_LIFECYCLE_CONFLICT.equals(exception.errorCode())) {
                log.info("恢复文件已再次删除或正在永久删除，跳过索引: fileNodeId={}", event.fileNodeId());
                channel.basicAck(deliveryTag, false);
                return;
            }
            log.error("恢复文件索引业务处理失败: fileNodeId={}", event.fileNodeId(), exception);
            channel.basicNack(deliveryTag, false, false);
        } catch (Throwable exception) {
            log.error("恢复文件索引处理失败: fileNodeId={}", event.fileNodeId(), exception);
            channel.basicNack(deliveryTag, false, false);
        }
    }
}
