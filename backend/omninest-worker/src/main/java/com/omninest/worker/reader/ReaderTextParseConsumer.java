package com.omninest.worker.reader;

import com.omninest.worker.runtime.ConditionalOnWorkerRuntime;

import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.reader.event.ReaderParseTaskEvent;
import com.omninest.modules.reader.service.ReaderTextParseTaskService;
import com.rabbitmq.client.Channel;
import java.io.IOException;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;

/**
 * 文本书籍解析任务消费者。
 *
 * @author OmniNest
 */
@Slf4j
@Component
@RequiredArgsConstructor
@ConditionalOnWorkerRuntime
public class ReaderTextParseConsumer {

    private final ReaderTextParseTaskService taskService;
    private final ReaderTextParseRetryService retryService;

    /**
     * 消费文本书籍解析消息。
     *
     * @param event 任务消息
     * @param message AMQP 消息
     * @param channel AMQP 通道
     * @throws IOException 确认消息失败时抛出
     */
    @RabbitListener(queues = QueueNames.READER_PARSE_QUEUE)
    public void handle(ReaderParseTaskEvent event, Message message, Channel channel) throws IOException {
        long deliveryTag = message.getMessageProperties().getDeliveryTag();
        try {
            taskService.process(event);
            channel.basicAck(deliveryTag, false);
        } catch (Throwable exception) {
            try {
                retryService.handleFailure(event, exception);
                channel.basicAck(deliveryTag, false);
            } catch (RuntimeException retryException) {
                log.error("文本书籍解析重试状态持久化失败: taskId={}", event.taskId(), retryException);
                channel.basicNack(deliveryTag, false, false);
            }
        }
    }
}
