package com.omninest.modules.sync.service;

import static org.assertj.core.api.Assertions.assertThat;

import com.omninest.modules.sync.config.SyncEventProperties;
import com.omninest.modules.sync.domain.SyncEventCheckpoint;
import com.omninest.modules.sync.repository.SyncEventCheckpointRepository;
import com.omninest.modules.sync.repository.SyncEventRepository;
import java.time.Instant;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.mockito.InOrder;
import org.mockito.Mockito;

/**
 * 同步事件保留清理服务单元测试。
 *
 * @author OmniNest
 */
class SyncEventRetentionServiceTest {

    private final SyncEventRepository eventRepository = Mockito.mock(SyncEventRepository.class);
    private final SyncEventCheckpointRepository checkpointRepository =
            Mockito.mock(SyncEventCheckpointRepository.class);
    private final SyncEventProperties properties = new SyncEventProperties();
    private final SyncEventRetentionService service = new SyncEventRetentionService(
            eventRepository,
            checkpointRepository,
            properties
    );

    @Test
    void cleanupAdvancesCheckpointBeforeBulkDelete() {
        SyncEventCheckpoint checkpoint = checkpoint(20L);
        Mockito.when(eventRepository.findFirstProtectedSequence(Mockito.any(Instant.class))).thenReturn(43L);
        Mockito.when(checkpointRepository.findForUpdateByCheckpointKey("retention_floor"))
                .thenReturn(Optional.of(checkpoint));
        Mockito.when(eventRepository.deletePublishedBefore(Mockito.any(Instant.class), Mockito.eq(42L)))
                .thenReturn(8);

        service.cleanup();

        assertThat(checkpoint.getSequenceNo()).isEqualTo(42L);
        InOrder order = Mockito.inOrder(checkpointRepository, eventRepository);
        order.verify(checkpointRepository).saveAndFlush(checkpoint);
        order.verify(eventRepository).deletePublishedBefore(Mockito.any(Instant.class), Mockito.eq(42L));
    }

    @Test
    void cleanupLeavesPendingEventsUntouchedWhenNoPublishedRowsExpired() {
        Mockito.when(eventRepository.findFirstProtectedSequence(Mockito.any(Instant.class))).thenReturn(1L);
        Mockito.when(checkpointRepository.findForUpdateByCheckpointKey("retention_floor"))
                .thenReturn(Optional.of(checkpoint(0L)));

        service.cleanup();

        Mockito.verify(eventRepository, Mockito.never())
                .deletePublishedBefore(Mockito.any(Instant.class), Mockito.anyLong());
    }

    private SyncEventCheckpoint checkpoint(long sequenceNo) {
        SyncEventCheckpoint checkpoint = new SyncEventCheckpoint();
        checkpoint.setId(UUID.randomUUID());
        checkpoint.setCheckpointKey("retention_floor");
        checkpoint.setSequenceNo(sequenceNo);
        checkpoint.setCreatedAt(Instant.now());
        checkpoint.setUpdatedAt(Instant.now());
        return checkpoint;
    }
}
