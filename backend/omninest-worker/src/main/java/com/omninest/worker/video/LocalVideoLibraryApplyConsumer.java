package com.omninest.worker.video;

import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.video.event.LocalVideoLibraryApplyRequestedEvent;
import com.omninest.modules.video.service.MediaLibraryApplyExecutor;
import com.omninest.modules.video.service.VideoLibraryApplyRetryService;
import com.omninest.worker.runtime.ConditionalOnWorkerRuntime;
import com.rabbitmq.client.Channel;
import java.io.IOException;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;

/** 用户确认后的本地媒体分批入库消费者。 */
@Slf4j
@Component
@RequiredArgsConstructor
@ConditionalOnWorkerRuntime
public class LocalVideoLibraryApplyConsumer {

    private final MediaLibraryApplyExecutor applyExecutor;
    private final VideoLibraryApplyRetryService retryService;

    /** 执行入库消息并确认消费结果。 */
    @RabbitListener(
            queues = QueueNames.LOCAL_VIDEO_LIBRARY_APPLY_QUEUE,
            containerFactory = "localMediaTaskListenerContainerFactory"
    )
    public void handle(
            LocalVideoLibraryApplyRequestedEvent event,
            Message message,
            Channel channel
    ) throws IOException {
        long deliveryTag = message.getMessageProperties().getDeliveryTag();
        try {
            log.info("收到本地媒体入库任务: taskId={}, scanRunId={}", event.taskId(), event.scanRunId());
            applyExecutor.execute(event);
            channel.basicAck(deliveryTag, false);
        } catch (Throwable exception) {
            try {
                retryService.handleFailure(event, exception);
                channel.basicAck(deliveryTag, false);
            } catch (RuntimeException retryException) {
                log.error("本地媒体入库失败状态持久化异常: taskId={}", event.taskId(), retryException);
                channel.basicNack(deliveryTag, false, false);
            }
        }
    }
}
