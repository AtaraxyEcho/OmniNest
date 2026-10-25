package com.omninest.worker.video;

import com.omninest.worker.runtime.ConditionalOnWorkerRuntime;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.task.service.TaskFailureRetryService;
import com.omninest.modules.video.event.TranscodeRequestedEvent;
import com.omninest.modules.video.service.TranscodeExecutionService;
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
public class TranscodeConsumer {
    private final TranscodeExecutionService transcodeExecutionService;
    private final TaskFailureRetryService taskFailureRetryService;

    @RabbitListener(queues = QueueNames.VIDEO_TRANSCODE_QUEUE, containerFactory = "transcodeListenerContainerFactory")
    public void handle(TranscodeRequestedEvent event, Message message, Channel channel) throws IOException {
        long deliveryTag = message.getMessageProperties().getDeliveryTag();
        try {
            log.info("收到转码任务: taskId={}, videoItemId={}, audioOnly={}, webOptimize={}",
                    event.taskId(), event.videoItemId(), event.audioOnly(), event.webOptimize());
            try {
                if (event.webOptimize()) {
                    transcodeExecutionService.executeWebOptimize(event.taskId(), event.videoItemId(), event.ownerUserId(), true);
                } else if (event.audioOnly()) {
                    transcodeExecutionService.executeAudioTranscode(event.taskId(), event.videoItemId(), event.ownerUserId(), true);
                } else {
                    transcodeExecutionService.execute(event.taskId(), event.videoItemId(), event.ownerUserId());
                }
            } catch (BusinessException e) {
                if (ErrorCode.TASK_NOT_FOUND.equals(e.errorCode())) {
                    log.warn("转码任务不存在（可能已清理），跳过: taskId={}", event.taskId());
                    channel.basicAck(deliveryTag, false);
                    return;
                }
                if (ErrorCode.FILE_NOT_FOUND.equals(e.errorCode())
                        || ErrorCode.FILE_LIFECYCLE_CONFLICT.equals(e.errorCode())) {
                    log.info("源视频已删除或正在永久删除，跳过转码消息: taskId={}", event.taskId());
                    channel.basicAck(deliveryTag, false);
                    return;
                }
                throw e;
            }
            channel.basicAck(deliveryTag, false);
        } catch (Throwable e) {
            log.error("转码处理失败: taskId={}", event.taskId(), e);
            handleFailure(event, deliveryTag, channel, e);
        }
    }

    private void handleFailure(
            TranscodeRequestedEvent event,
            long deliveryTag,
            Channel channel,
            Throwable exception
    ) throws IOException {
        try {
            taskFailureRetryService.handleFailure(
                    event.taskId(), QueueNames.VIDEO_TRANSCODE_ROUTING_KEY, event, exception);
            channel.basicAck(deliveryTag, false);
        } catch (RuntimeException stateException) {
            log.error("转码失败状态写入失败，将重新投递原消息: taskId={}, errorType={}",
                    event.taskId(), stateException.getClass().getSimpleName(), stateException);
            channel.basicNack(deliveryTag, false, true);
        }
    }
}
