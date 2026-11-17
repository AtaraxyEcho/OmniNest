package com.omninest.modules.sync.realtime;

import static org.assertj.core.api.Assertions.assertThat;

import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncEventEnvelope;
import com.omninest.common.sync.SyncScope;
import com.omninest.modules.notification.dto.NotificationDto;
import com.omninest.modules.notification.service.NotificationRealtimeGateway;
import com.omninest.modules.notification.service.NotificationService;
import com.omninest.modules.sync.dto.SyncDtos.SyncEventDto;
import java.time.Instant;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.Mockito;
import org.springframework.messaging.simp.SimpMessagingTemplate;

/**
 * RabbitMQ 同步事件到 STOMP 用户目标转发测试。
 *
 * @author OmniNest
 */
class RabbitSyncEventConsumerTest {

    private final SimpMessagingTemplate messagingTemplate = Mockito.mock(SimpMessagingTemplate.class);
    private final NotificationService notificationService = Mockito.mock(NotificationService.class);
    private final NotificationRealtimeGateway notificationRealtimeGateway =
            Mockito.mock(NotificationRealtimeGateway.class);
    private final RabbitSyncEventConsumer consumer = new RabbitSyncEventConsumer(
            messagingTemplate,
            notificationService,
            notificationRealtimeGateway
    );

    @Test
    void onSyncEventRemovesInternalRecipientFieldFromClientPayload() {
        UUID userId = UUID.randomUUID();
        SyncEventEnvelope envelope = envelope(userId, 1, 1);

        consumer.onSyncEvent(envelope);

        ArgumentCaptor<SyncEventDto> event = ArgumentCaptor.forClass(SyncEventDto.class);
        Mockito.verify(messagingTemplate).convertAndSendToUser(
                Mockito.eq(userId.toString()),
                Mockito.eq("/queue/sync"),
                event.capture()
        );
        assertThat(event.getValue().eventId()).isEqualTo(envelope.eventId());
        assertThat(event.getValue().sequenceNo()).isEqualTo(envelope.sequenceNo());
    }

    @Test
    void onSyncEventIgnoresUnsupportedContractVersion() {
        consumer.onSyncEvent(envelope(UUID.randomUUID(), 2, 1));

        Mockito.verifyNoInteractions(messagingTemplate);
    }

    @Test
    void onNotificationCreatedProjectsCommittedNotificationOnEveryApiInstance() {
        UUID userId = UUID.randomUUID();
        UUID notificationId = UUID.randomUUID();
        Instant now = Instant.now();
        NotificationDto notification = new NotificationDto(
                notificationId,
                "TASK_COMPLETED",
                "任务完成",
                "任务已经完成",
                false,
                now
        );
        SyncEventEnvelope envelope = new SyncEventEnvelope(
                1,
                1,
                UUID.randomUUID(),
                34L,
                userId,
                SyncScope.NOTIFICATIONS,
                "NOTIFICATION",
                notificationId.toString(),
                SyncAction.CREATED,
                null,
                Map.of(),
                now.minusSeconds(1),
                now
        );
        Mockito.when(notificationService.findForRealtime(userId, notificationId))
                .thenReturn(Optional.of(notification));

        consumer.onSyncEvent(envelope);

        Mockito.verify(notificationRealtimeGateway).send(userId, notification);
    }

    @Test
    void onNotificationProjectionFailureDoesNotFailSyncEventConsumption() {
        UUID userId = UUID.randomUUID();
        UUID notificationId = UUID.randomUUID();
        Instant now = Instant.now();
        SyncEventEnvelope envelope = new SyncEventEnvelope(
                1,
                1,
                UUID.randomUUID(),
                35L,
                userId,
                SyncScope.NOTIFICATIONS,
                "NOTIFICATION",
                notificationId.toString(),
                SyncAction.CREATED,
                null,
                Map.of(),
                now.minusSeconds(1),
                now
        );
        Mockito.when(notificationService.findForRealtime(userId, notificationId))
                .thenThrow(new IllegalStateException("WebSocket unavailable"));

        consumer.onSyncEvent(envelope);

        Mockito.verify(messagingTemplate).convertAndSendToUser(
                Mockito.eq(userId.toString()),
                Mockito.eq("/queue/sync"),
                Mockito.any(SyncEventDto.class)
        );
    }

    private SyncEventEnvelope envelope(UUID userId, int schemaVersion, int routingVersion) {
        Instant now = Instant.now();
        return new SyncEventEnvelope(
                schemaVersion,
                routingVersion,
                UUID.randomUUID(),
                33L,
                userId,
                SyncScope.FILES,
                "FILE_NODE",
                UUID.randomUUID().toString(),
                SyncAction.UPDATED,
                5L,
                Map.of("parentId", UUID.randomUUID().toString()),
                now.minusSeconds(1),
                now
        );
    }
}
