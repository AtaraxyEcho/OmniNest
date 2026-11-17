package com.omninest.modules.sync.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.omninest.common.messaging.QueueNames;
import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncEventEnvelope;
import com.omninest.common.sync.SyncScope;
import com.omninest.modules.sync.config.SyncEventProperties;
import java.time.Instant;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.Mockito;
import org.springframework.amqp.rabbit.connection.CorrelationData;
import org.springframework.amqp.rabbit.core.RabbitTemplate;

/**
 * RabbitMQ 同步事件发布器单元测试。
 *
 * @author OmniNest
 */
class RabbitSyncEventPublisherTest {

    private final RabbitTemplate rabbitTemplate = Mockito.mock(RabbitTemplate.class);
    private final SyncEventProperties properties = new SyncEventProperties();
    private final RabbitSyncEventPublisher publisher = new RabbitSyncEventPublisher(
            rabbitTemplate,
            properties
    );

    @Test
    void publishWaitsForAckAndUsesScopeRoutingKey() {
        completeConfirm(true, null);
        ClaimedSyncEvent event = event();
        Instant publishedAt = Instant.parse("2026-07-17T03:00:00Z");

        publisher.publish(event, publishedAt);

        ArgumentCaptor<SyncEventEnvelope> envelope = ArgumentCaptor.forClass(SyncEventEnvelope.class);
        Mockito.verify(rabbitTemplate).convertAndSend(
                Mockito.eq(QueueNames.SYNC_EVENT_EXCHANGE),
                Mockito.eq("sync.user.files"),
                envelope.capture(),
                Mockito.any(CorrelationData.class)
        );
        assertThat(envelope.getValue().eventId()).isEqualTo(event.id());
        assertThat(envelope.getValue().recipientUserId()).isEqualTo(event.recipientUserId());
        assertThat(envelope.getValue().publishedAt()).isEqualTo(publishedAt);
    }

    @Test
    void publishRejectsBrokerNack() {
        completeConfirm(false, "broker rejected");

        assertThatThrownBy(() -> publisher.publish(event(), Instant.now()))
                .isInstanceOf(SyncEventPublishException.class)
                .hasMessageContaining("拒绝同步事件");
    }

    private void completeConfirm(boolean ack, String reason) {
        Mockito.doAnswer(invocation -> {
            CorrelationData correlationData = invocation.getArgument(3);
            correlationData.getFuture().complete(new CorrelationData.Confirm(ack, reason));
            return null;
        }).when(rabbitTemplate).convertAndSend(
                Mockito.anyString(),
                Mockito.anyString(),
                Mockito.any(SyncEventEnvelope.class),
                Mockito.any(CorrelationData.class)
        );
    }

    private ClaimedSyncEvent event() {
        return new ClaimedSyncEvent(
                UUID.randomUUID(),
                19L,
                UUID.randomUUID(),
                SyncScope.FILES,
                "FILE_NODE",
                UUID.randomUUID().toString(),
                SyncAction.UPDATED,
                4L,
                Map.of("parentId", UUID.randomUUID().toString()),
                Instant.parse("2026-07-17T02:59:00Z"),
                0
        );
    }
}
