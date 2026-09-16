package com.omninest.worker.index;

import com.omninest.worker.runtime.ConditionalOnWorkerRuntime;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.file.event.FileUploadedEvent;
import com.omninest.worker.file.FilePostProcessingTaskTracker;
import com.rabbitmq.client.Channel;
import java.io.IOException;
import java.util.Map;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;

/**
 * 文件索引队列消费者。
 * 同步维护 sys_tasks 生命周期：领取 → 执行 → 完成 / 失败重试。
 *
 * @author OmniNest
 */
@Slf4j
@Component
@RequiredArgsConstructor
@ConditionalOnWorkerRuntime
public class FileIndexConsumer {
    private static final String TASK_TYPE = "FILE_INDEX";
    private final FileIndexTaskService taskService;
    private final FilePostProcessingTaskTracker taskTracker;

    /**
     * 处理文件索引消息并确认消费结果。
     *
     * @param event 文件上传事件
     * @param message AMQP 消息
     * @param channel RabbitMQ 通道
     * @throws IOException ACK 或 NACK 失败时抛出
     */
    @RabbitListener(queues = QueueNames.FILE_INDEX_QUEUE)
    public void handle(FileUploadedEvent event, Message message, Channel channel) throws IOException {
        long deliveryTag = message.getMessageProperties().getDeliveryTag();
        FilePostProcessingTaskTracker.TrackedTask tracked =
                taskTracker.begin(event.ownerUserId(), TASK_TYPE, event.fileNodeId(), "INDEXING");
        if (tracked.shouldSkip()) {
            log.info("文件索引任务已被其他消费者领取，跳过重复处理: fileNodeId={}", event.fileNodeId());
            channel.basicAck(deliveryTag, false);
            return;
        }
        try {
            log.info("收到文件索引任务: fileNodeId={}, fileName={}", event.fileNodeId(), event.fileName());
            taskService.process(event);
            taskTracker.complete(tracked.taskId(), Map.of("indexed", true));
            channel.basicAck(deliveryTag, false);
        } catch (BusinessException exception) {
            if (ErrorCode.FILE_NOT_FOUND.equals(exception.errorCode())
                    || ErrorCode.FILE_LIFECYCLE_CONFLICT.equals(exception.errorCode())) {
                log.info("源文件已删除或正在永久删除，跳过文件索引任务: fileNodeId={}", event.fileNodeId());
                taskTracker.complete(tracked.taskId(), Map.of("skipped", true, "reason", "SOURCE_DELETED"));
                channel.basicAck(deliveryTag, false);
                return;
            }
            log.error("文件索引业务处理失败: fileNodeId={}", event.fileNodeId(), exception);
            taskTracker.handleFailure(
                    TASK_TYPE, QueueNames.FILE_INDEX_ROUTING_KEY, tracked.taskId(), event, exception);
            channel.basicAck(deliveryTag, false);
        } catch (Throwable e) {
            log.error("文件索引处理失败: fileNodeId={}", event.fileNodeId(), e);
            taskTracker.handleFailure(TASK_TYPE, QueueNames.FILE_INDEX_ROUTING_KEY, tracked.taskId(), event, e);
            channel.basicAck(deliveryTag, false);
        }
    }
}
