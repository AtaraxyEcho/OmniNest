package com.omninest.worker.dlq;

import com.omninest.common.json.JsonSupport;
import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.task.service.TaskRecordService;
import com.omninest.worker.runtime.ConditionalOnWorkerRuntime;
import com.rabbitmq.client.Channel;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.Optional;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;
import tools.jackson.databind.JsonNode;

/**
 * 死信队列消费者，解析消息中的任务标识并委托任务服务更新状态。
 *
 * @author OmniNest
 */
@Slf4j
@Component
@RequiredArgsConstructor
@ConditionalOnWorkerRuntime
public class DeadLetterConsumer {

    private final TaskRecordService taskRecordService;

    /**
     * 处理死信消息并确认消费结果。
     *
     * @param message AMQP 消息
     * @param channel RabbitMQ 通道
     * @throws IOException ACK 或 NACK 失败时抛出
     */
    @RabbitListener(queues = QueueNames.DEAD_LETTER_QUEUE)
    public void handle(Message message, Channel channel) throws IOException {
        long deliveryTag = message.getMessageProperties().getDeliveryTag();
        try {
            String body = new String(message.getBody(), StandardCharsets.UTF_8);
            String exchange = message.getMessageProperties().getReceivedExchange();
            String routingKey = message.getMessageProperties().getReceivedRoutingKey();
            log.error("收到死信消息: exchange={}, routingKey={}, bodyLength={}",
                    exchange, routingKey, body.length());

            extractTaskId(message, body).ifPresent(taskId -> {
                boolean updated = taskRecordService.markDeadLetter(
                        taskId,
                        DeadLetterDescriptions.describe(message, body, routingKey),
                        DeadLetterDescriptions.stackSummary(body)
                );
                if (updated) {
                    log.info("任务状态已更新为 DLQ: taskId={}", taskId);
                } else {
                    log.warn("死信消息关联的任务不存在或已处于终态: taskId={}", taskId);
                }
            });
            channel.basicAck(deliveryTag, false);
        } catch (Throwable e) {
            log.error("死信处理失败", e);
            channel.basicNack(deliveryTag, false, false);
        }
    }

    /**
     * 尝试从消息头或 JSON body 中提取 taskId。
     */
    private Optional<UUID> extractTaskId(Message message, String body) {
        Object taskIdHeader = message.getMessageProperties().getHeaders().get("taskId");
        if (taskIdHeader != null) {
            try {
                return Optional.of(UUID.fromString(taskIdHeader.toString()));
            } catch (IllegalArgumentException exception) {
                log.debug("死信消息头 taskId 无效，继续解析消息体");
            }
        }
        try {
            JsonNode json = JsonSupport.readTree(body);
            if (json != null && json.has("taskId")) {
                return Optional.of(UUID.fromString(json.path("taskId").asString()));
            }
        } catch (RuntimeException exception) {
            log.debug("死信消息体不包含有效任务标识");
        }
        return Optional.empty();
    }
}
