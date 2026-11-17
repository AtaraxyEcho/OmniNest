package com.omninest.modules.sync.service;

import com.omninest.common.messaging.QueueNames;
import com.omninest.common.sync.SyncEventEnvelope;
import com.omninest.modules.sync.config.SyncEventProperties;
import java.time.Instant;
import java.util.Locale;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.rabbit.connection.CorrelationData;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.stereotype.Service;

/**
 * 使用 Publisher Confirm 发布同步事件信封。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class RabbitSyncEventPublisher {

    private static final int SCHEMA_VERSION = 1;
    private static final int ROUTING_VERSION = 1;

    private final RabbitTemplate rabbitTemplate;
    private final SyncEventProperties properties;

    /**
     * 发布事件并等待 Broker 确认。
     *
     * @param event 已认领事件
     * @param publishedAt 发布时间
     */
    public void publish(ClaimedSyncEvent event, Instant publishedAt) {
        CorrelationData correlationData = new CorrelationData(event.id().toString());
        rabbitTemplate.convertAndSend(
                QueueNames.SYNC_EVENT_EXCHANGE,
                routingKey(event),
                envelope(event, publishedAt),
                correlationData
        );
        CorrelationData.Confirm confirm = awaitConfirm(correlationData);
        if (!confirm.ack()) {
            throw new SyncEventPublishException("RabbitMQ 拒绝同步事件: " + confirm.reason());
        }
        if (correlationData.getReturned() != null) {
            log.warn("同步事件未路由但已获确认: eventId={}, sequenceNo={}", event.id(), event.sequenceNo());
        }
    }

    private CorrelationData.Confirm awaitConfirm(CorrelationData correlationData) {
        try {
            long timeout = Math.max(1L, properties.getOutbox().getConfirmTimeoutMillis());
            return correlationData.getFuture().get(timeout, TimeUnit.MILLISECONDS);
        } catch (InterruptedException ex) {
            Thread.currentThread().interrupt();
            throw new SyncEventPublishException("等待 RabbitMQ 发布确认时线程中断", ex);
        } catch (ExecutionException | TimeoutException ex) {
            throw new SyncEventPublishException("等待 RabbitMQ 发布确认失败", ex);
        }
    }

    private String routingKey(ClaimedSyncEvent event) {
        return "sync.user." + event.scope().name().toLowerCase(Locale.ROOT);
    }

    private SyncEventEnvelope envelope(ClaimedSyncEvent event, Instant publishedAt) {
        return new SyncEventEnvelope(
                SCHEMA_VERSION,
                ROUTING_VERSION,
                event.id(),
                event.sequenceNo(),
                event.recipientUserId(),
                event.scope(),
                event.resourceType(),
                event.resourceId(),
                event.action(),
                event.resourceVersion(),
                event.hints(),
                event.occurredAt(),
                publishedAt
        );
    }
}
