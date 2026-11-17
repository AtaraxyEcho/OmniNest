package com.omninest.common.config;

import com.omninest.common.messaging.QueueNames;
import io.micrometer.core.instrument.Gauge;
import io.micrometer.core.instrument.MeterRegistry;
import jakarta.annotation.PostConstruct;
import java.util.Map;
import java.util.Properties;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicLong;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.core.AmqpAdmin;
import org.springframework.amqp.rabbit.core.RabbitAdmin;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * 在 API 角色中采集持久队列深度并记录分级积压告警。
 *
 * @author OmniNest
 */
@Slf4j
@Component
@RequiredArgsConstructor
@ConditionalOnProperty(
        prefix = "omninest.runtime",
        name = "role",
        havingValue = "api",
        matchIfMissing = true
)
public class RabbitQueueBacklogMonitor {
    private static final String QUEUE_DEPTH_METRIC = "omninest.rabbitmq.queue.messages";

    private final AmqpAdmin amqpAdmin;
    private final MeterRegistry meterRegistry;
    private final RabbitMessagingProperties properties;
    private final Map<String, AtomicLong> queueDepths = new ConcurrentHashMap<>();

    @PostConstruct
    void registerMetrics() {
        for (String queueName : QueueNames.durableQueues()) {
            AtomicLong depth = new AtomicLong();
            queueDepths.put(queueName, depth);
            Gauge.builder(QUEUE_DEPTH_METRIC, depth, AtomicLong::get)
                    .description("RabbitMQ 持久队列中的就绪消息数量")
                    .tag("queue", queueName)
                    .register(meterRegistry);
        }
    }

    /**
     * 采集队列深度并在超过阈值时记录告警。
     */
    @Scheduled(fixedDelayString = "${omninest.messaging.rabbit.backlog-poll-interval:60s}")
    public void inspect() {
        if (!properties.isBacklogMonitoringEnabled()) {
            return;
        }
        long warningThreshold = Math.max(1L, properties.getBacklogWarningMessages());
        long criticalThreshold = Math.max(warningThreshold, properties.getBacklogCriticalMessages());
        int failedQueues = 0;

        for (String queueName : QueueNames.durableQueues()) {
            try {
                long depth = queueDepth(queueName);
                queueDepths.get(queueName).set(depth);
                logBacklog(queueName, depth, warningThreshold, criticalThreshold);
            } catch (RuntimeException exception) {
                queueDepths.get(queueName).set(-1L);
                failedQueues++;
            }
        }
        if (failedQueues > 0) {
            log.warn("RabbitMQ 队列积压采样部分失败: failedQueues={}", failedQueues);
        }
    }

    private long queueDepth(String queueName) {
        Properties queueProperties = amqpAdmin.getQueueProperties(queueName);
        if (queueProperties == null) {
            return 0L;
        }
        Object value = queueProperties.get(RabbitAdmin.QUEUE_MESSAGE_COUNT);
        if (value instanceof Number number) {
            return Math.max(0L, number.longValue());
        }
        return 0L;
    }

    private void logBacklog(String queueName, long depth, long warningThreshold, long criticalThreshold) {
        if (depth >= criticalThreshold) {
            log.error("RabbitMQ 队列严重积压: queue={}, messages={}, threshold={}",
                    queueName, depth, criticalThreshold);
            return;
        }
        if (depth >= warningThreshold) {
            log.warn("RabbitMQ 队列积压: queue={}, messages={}, threshold={}",
                    queueName, depth, warningThreshold);
        }
    }
}
