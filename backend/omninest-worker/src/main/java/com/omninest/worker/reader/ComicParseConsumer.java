package com.omninest.worker.reader;

import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.reader.event.ComicParseTaskEvent;
import com.omninest.modules.reader.service.ComicParseTaskService;
import com.rabbitmq.client.Channel;
import java.io.IOException;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.boot.autoconfigure.condition.ConditionalOnExpression;
import org.springframework.stereotype.Component;

/**
 * 漫画解析任务消费者，从 RabbitMQ 消费 CBZ/ZIP/EPUB 解析任务。
 *
 * @author OmniNest
 */
@Slf4j
@Component
@RequiredArgsConstructor
@ConditionalOnExpression("'${omninest.runtime.role:api}' == 'worker' || "
        + "('${omninest.runtime.role:api}' == 'api' && "
        + "(${omninest.runtime.embedded-worker-enabled:false} || ${reader.comic-parser.consume-in-api:false}))")
public class ComicParseConsumer {

    private final ComicParseTaskService taskService;
    private final ComicParseRetryService retryService;

    /**
     * 处理漫画解析任务。
     *
     * @param event 解析任务事件
     * @param message AMQP 消息
     * @param channel RabbitMQ 通道
     * @throws IOException ack/nack 失败时抛出
     */
    @RabbitListener(queues = QueueNames.COMIC_PARSE_QUEUE)
    public void handle(ComicParseTaskEvent event, Message message, Channel channel) throws IOException {
        long deliveryTag = message.getMessageProperties().getDeliveryTag();
        try {
            log.info("收到漫画解析任务: itemId={}, sourceId={}, fileFormat={}, isRetry={}",
                    event.itemId(), event.sourceId(), event.fileFormat(), event.isRetry());
            taskService.process(event);
            channel.basicAck(deliveryTag, false);
        } catch (Throwable exception) {
            log.error("漫画解析基础设施异常，将按任务策略重试: taskId={}, itemId={}, sourceId={}",
                    event.taskId(), event.itemId(), event.sourceId(), exception);
            try {
                retryService.handleFailure(event, exception);
                channel.basicAck(deliveryTag, false);
            } catch (RuntimeException retryException) {
                log.error("漫画解析重试状态持久化失败: taskId={}", event.taskId(), retryException);
                channel.basicNack(deliveryTag, false, false);
            }
        }
    }
}
