package com.omninest.modules.sync.service;

import static org.assertj.core.api.Assertions.assertThat;

import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncScope;
import com.omninest.modules.sync.config.SyncEventProperties;
import com.omninest.modules.sync.domain.SyncEvent;
import com.omninest.modules.sync.repository.SyncEventRepository;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.Mockito;

/**
 * Outbox 数据库状态服务单元测试。
 *
 * @author OmniNest
 */
class SyncOutboxStateServiceTest {

    private final SyncEventRepository repository = Mockito.mock(SyncEventRepository.class);
    private final SyncEventProperties properties = properties();
    private final SyncOutboxStateService service = new SyncOutboxStateService(repository, properties);

    @Test
    void claimBatchWritesInstanceLeaseAndReturnsSnapshot() {
        Instant now = Instant.parse("2026-07-17T03:00:00Z");
        SyncEvent event = event(12L, 2);
        Mockito.when(repository.findClaimableEvents(now, 100))
                .thenReturn(List.of(event));

        List<ClaimedSyncEvent> result = service.claimBatch(now);

        assertThat(result).hasSize(1);
        assertThat(result.getFirst().sequenceNo()).isEqualTo(12L);
        assertThat(event.getPublishStatus()).isEqualTo("PUBLISHING");
        assertThat(event.getLockedBy()).isEqualTo("api-test-1");
        assertThat(event.getLockedUntil()).isEqualTo(now.plusSeconds(30));
        Mockito.verify(repository).findClaimableEvents(now, 100);
        Mockito.verify(repository).flush();
    }

    @Test
    void markFailedIncrementsAttemptAndAppliesBackoff() {
        Instant failedAt = Instant.parse("2026-07-17T03:00:00Z");
        ClaimedSyncEvent event = claimedEvent(3);
        Mockito.when(repository.markPublishFailed(
                        Mockito.eq(event.id()),
                        Mockito.eq("api-test-1"),
                        Mockito.eq(4),
                        Mockito.any(Instant.class),
                        Mockito.eq(failedAt)
                ))
                .thenReturn(1);

        boolean updated = service.markFailed(event, failedAt);

        assertThat(updated).isTrue();
        ArgumentCaptor<Instant> availableAt = ArgumentCaptor.forClass(Instant.class);
        Mockito.verify(repository).markPublishFailed(
                Mockito.eq(event.id()),
                Mockito.eq("api-test-1"),
                Mockito.eq(4),
                availableAt.capture(),
                Mockito.eq(failedAt)
        );
        assertThat(availableAt.getValue()).isEqualTo(failedAt.plusSeconds(120));
    }

    private SyncEventProperties properties() {
        SyncEventProperties value = new SyncEventProperties();
        value.getOutbox().setInstanceId("api-test-1");
        value.getOutbox().setBatchSize(100);
        value.getOutbox().setLeaseSeconds(30);
        return value;
    }

    private SyncEvent event(long sequenceNo, int attempts) {
        SyncEvent event = new SyncEvent();
        event.setId(UUID.randomUUID());
        event.setSequenceNo(sequenceNo);
        event.setRecipientUserId(UUID.randomUUID());
        event.setScope(SyncScope.FILES);
        event.setResourceType("FILE_NODE");
        event.setResourceId(UUID.randomUUID().toString());
        event.setAction(SyncAction.UPDATED);
        event.setPayload(Map.of("parentId", UUID.randomUUID().toString()));
        event.setCreatedAt(Instant.parse("2026-07-17T02:59:00Z"));
        event.setPublishAttempts(attempts);
        return event;
    }

    private ClaimedSyncEvent claimedEvent(int attempts) {
        return new ClaimedSyncEvent(
                UUID.randomUUID(),
                12L,
                UUID.randomUUID(),
                SyncScope.FILES,
                "FILE_NODE",
                UUID.randomUUID().toString(),
                SyncAction.UPDATED,
                3L,
                Map.of(),
                Instant.parse("2026-07-17T02:59:00Z"),
                attempts
        );
    }
}
