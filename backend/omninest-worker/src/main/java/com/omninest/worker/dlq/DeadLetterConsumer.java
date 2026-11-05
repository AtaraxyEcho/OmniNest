package com.omninest.worker.dlq;

import com.omninest.common.json.JsonSupport;
import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.task.service.TaskRecordService;
import com.omninest.worker.runtime.ConditionalOnWorkerRuntime;
import com.rabbitmq.client.Channel;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
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

    /** 无任务记录、进入死信后没有补跑入口的索引同步队列。 */
    private static final Set<String> UNTRACKED_INDEX_ROUTING_KEYS = Set.of(
            "file.index.sync",
            "photo.index",
            "file.index.user-purge",
            "photo.index.user-purge"
    );

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

            Optional<UUID> taskId = extractTaskId(message, body);
            if (taskId.isPresent()) {
                boolean updated = taskRecordService.markDeadLetter(
                        taskId.get(),
                        DeadLetterDescriptions.describe(message, body, routingKey),
                        DeadLetterDescriptions.stackSummary(body)
                );
                if (updated) {
                    log.info("任务状态已更新为 DLQ: taskId={}", taskId.get());
                } else {
                    log.warn("死信消息关联的任务不存在或已处于终态: taskId={}", taskId.get());
                }
            } else {
                flagUntrackedIndexDeadLetter(message, routingKey);
            }
            channel.basicAck(deliveryTag, false);
        } catch (Throwable e) {
            log.error("死信处理失败", e);
            channel.basicNack(deliveryTag, false, false);
        }
    }

    /**
     * 无 taskId 的索引同步死信：不写 sys_tasks（这些消费者不感知任务状态，
     * 补一条 QUEUED 行会被恢复器每 30 分钟无限重投），只把原始路由键记进日志。
     *
     * @param message AMQP 消息
     * @param receivedRoutingKey 死信队列上恒为 task.dlq 的接收路由键
     */
    private void flagUntrackedIndexDeadLetter(Message message, String receivedRoutingKey) {
        String originalRoutingKey = extractOriginalRoutingKey(message);
        if (originalRoutingKey == null || !UNTRACKED_INDEX_ROUTING_KEYS.contains(originalRoutingKey)) {
            log.debug("死信消息无任务标识且不属于索引同步队列: routingKey={}", receivedRoutingKey);
            return;
        }
        log.error("索引同步消息进入死信，需人工重建索引: originalRoutingKey={}, receivedRoutingKey={}",
                originalRoutingKey, receivedRoutingKey);
    }

    /**
     * 从 x-death 头提取原始路由键。
     *
     * <p>死信队列上的 receivedRoutingKey 恒为 task.dlq，只有 x-death 记录了
     * 消息被拒绝前真正的路由。</p>
     *
     * @param message AMQP 消息
     * @return 原始路由键；缺失时返回 null
     */
    @SuppressWarnings("unchecked")
    private String extractOriginalRoutingKey(Message message) {
        Object header = message.getMessageProperties().getXDeathHeader();
        if (!(header instanceof List<?> deaths) || deaths.isEmpty()) {
            return null;
        }
        Object first = deaths.get(0);
        if (!(first instanceof Map<?, ?> death)) {
            return null;
        }
        Object routingKeys = death.get("routing-keys");
        if (routingKeys instanceof List<?> keys && !keys.isEmpty()) {
            Object key = keys.get(0);
            return key == null ? null : key.toString();
        }
        return null;
    }

    /**
     * 从消息头或 JSON body 中提取 taskId。
     *
     * <p>头与体两条通道都保留：任务消息由发布侧写头，业务事件类死信只能从体里取。</p>
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
