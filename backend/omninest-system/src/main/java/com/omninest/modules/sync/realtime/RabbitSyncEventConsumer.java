package com.omninest.modules.sync.realtime;

import com.omninest.common.sync.SyncEventEnvelope;
import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncScope;
import com.omninest.modules.notification.port.NotificationRealtimeQuery;
import com.omninest.modules.notification.service.NotificationRealtimeGateway;
import com.omninest.modules.sync.dto.SyncDtos.SyncEventDto;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.stereotype.Component;

/**
 * 将 RabbitMQ 广播事件转发到当前 API 实例的用户 STOMP 目标。
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
public class RabbitSyncEventConsumer {

    private static final int SUPPORTED_SCHEMA_VERSION = 1;
    private static final int SUPPORTED_ROUTING_VERSION = 1;

    private final SimpMessagingTemplate messagingTemplate;
    private final NotificationRealtimeQuery notificationService;
    private final NotificationRealtimeGateway notificationRealtimeGateway;

    /**
     * 消费当前实例临时队列中的同步事件并执行用户定向投递。
     *
     * @param envelope 内部同步事件信封
     */
    @RabbitListener(
            queues = "#{syncEventInstanceQueue.name}",
            containerFactory = "broadcastListenerContainerFactory"
    )
    public void onSyncEvent(SyncEventEnvelope envelope) {
        try {
            if (!supported(envelope)) {
                return;
            }
            SyncEventDto event = new SyncEventDto(
                    envelope.schemaVersion(),
                    envelope.eventId(),
                    envelope.sequenceNo(),
                    envelope.scope().name(),
                    envelope.resourceType(),
                    envelope.resourceId(),
                    envelope.action().name(),
                    envelope.resourceVersion(),
                    envelope.hints(),
                    envelope.occurredAt()
            );
            messagingTemplate.convertAndSendToUser(
                    envelope.recipientUserId().toString(),
                    "/queue/sync",
                    event
            );
            projectNotification(envelope);
        } catch (Throwable t) {
            log.error("同步事件处理失败: eventId={}", envelope == null ? null : envelope.eventId(), t);
        }
    }

    private void projectNotification(SyncEventEnvelope envelope) {
        if (envelope.scope() != SyncScope.NOTIFICATIONS
                || envelope.action() != SyncAction.CREATED
                || envelope.resourceId() == null) {
            return;
        }
        try {
            UUID notificationId = UUID.fromString(envelope.resourceId());
            notificationService.findForRealtime(envelope.recipientUserId(), notificationId)
                    .ifPresent(notification -> notificationRealtimeGateway.send(
                            envelope.recipientUserId(),
                            notification
                    ));
        } catch (IllegalArgumentException ex) {
            log.warn("忽略通知标识无效的同步事件: eventId={}, resourceId={}",
                    envelope.eventId(), envelope.resourceId());
        } catch (Exception ex) {
            log.warn("通知实时投递失败，不影响同步事件消费: eventId={}, userId={}",
                    envelope.eventId(), envelope.recipientUserId(), ex);
        }
    }

    private boolean supported(SyncEventEnvelope envelope) {
        if (envelope == null
                || envelope.recipientUserId() == null
                || envelope.scope() == null
                || envelope.action() == null) {
            log.warn("忽略字段不完整的同步事件信封");
            return false;
        }
        if (envelope.schemaVersion() != SUPPORTED_SCHEMA_VERSION
                || envelope.routingVersion() != SUPPORTED_ROUTING_VERSION) {
            log.warn(
                    "忽略不兼容的同步事件信封: schemaVersion={}, routingVersion={}",
                    envelope.schemaVersion(),
                    envelope.routingVersion()
            );
            return false;
        }
        return true;
    }
}
