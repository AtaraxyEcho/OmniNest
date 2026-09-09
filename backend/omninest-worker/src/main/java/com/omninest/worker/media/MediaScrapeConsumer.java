package com.omninest.worker.media;

import com.omninest.worker.runtime.ConditionalOnWorkerRuntime;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.task.service.TaskRecordService;
import com.omninest.modules.video.event.MediaScrapeRequestedEvent;
import com.omninest.modules.video.service.MovieScrapeExecutionService;
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
public class MediaScrapeConsumer {

    private final MovieScrapeExecutionService scrapeExecutionService;
    private final TaskRecordService taskRecordService;
    private final MediaScrapeRetryService mediaScrapeRetryService;

    @RabbitListener(queues = QueueNames.MEDIA_QUEUE)
    public void handle(MediaScrapeRequestedEvent event, Message message, Channel channel) throws IOException {
        long deliveryTag = message.getMessageProperties().getDeliveryTag();
        try {
            log.info("收到媒体刮削任务: taskId={}, fileNodeId={}", event.taskId(), event.fileNodeId());
            try {
                scrapeExecutionService.execute(event);
            } catch (BusinessException e) {
                if (ErrorCode.TASK_NOT_FOUND.equals(e.errorCode())) {
                    log.warn("刮削任务不存在（可能已清理），跳过: taskId={}", event.taskId());
                    channel.basicAck(deliveryTag, false);
                    return;
                }
                if (ErrorCode.FILE_NOT_FOUND.equals(e.errorCode())
                        || ErrorCode.FILE_LIFECYCLE_CONFLICT.equals(e.errorCode())) {
                    taskRecordService.markCancelled(event.taskId());
                    log.info("媒体源文件已删除或正在永久删除，取消刮削任务: taskId={}, fileNodeId={}",
                            event.taskId(), event.fileNodeId());
                    channel.basicAck(deliveryTag, false);
                    return;
                }
                mediaScrapeRetryService.handleFailure(event, e);
            } catch (Exception e) {
                mediaScrapeRetryService.handleFailure(event, e);
            }
            channel.basicAck(deliveryTag, false);
        } catch (Exception e) {
            // 重试状态持久化失败时不再吞异常后 ack，消息转入死信队列保留现场。
            log.error("媒体刮削处理失败: taskId={}", event.taskId(), e);
            channel.basicNack(deliveryTag, false, false);
        }
    }
}
