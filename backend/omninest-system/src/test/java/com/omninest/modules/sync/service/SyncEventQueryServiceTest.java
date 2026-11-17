package com.omninest.modules.sync.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncScope;
import com.omninest.modules.sync.domain.SyncEvent;
import com.omninest.modules.sync.domain.SyncEventCheckpoint;
import com.omninest.modules.sync.dto.SyncDtos.SyncEventPageDto;
import com.omninest.modules.sync.repository.SyncEventCheckpointRepository;
import com.omninest.modules.sync.repository.SyncEventRepository;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.data.domain.Pageable;

/**
 * 同步事件游标查询服务单元测试。
 *
 * @author OmniNest
 */
class SyncEventQueryServiceTest {

    private final SyncEventRepository eventRepository = mock(SyncEventRepository.class);
    private final SyncEventCheckpointRepository checkpointRepository =
            mock(SyncEventCheckpointRepository.class);
    private final SyncEventQueryService service = new SyncEventQueryService(
            eventRepository,
            checkpointRepository
    );

    @BeforeEach
    void setUp() {
        when(checkpointRepository.findByCheckpointKey("retention_floor"))
                .thenReturn(Optional.of(checkpoint(5L)));
        when(eventRepository.findLatestSequenceNo()).thenReturn(20L);
    }

    @Test
    void eventsFiltersByCurrentUserAndAdvancesToGlobalHead() {
        UUID userId = UUID.randomUUID();
        when(eventRepository.findVisibleEvents(eq(userId), eq(5L), eq(20L), any(Pageable.class)))
                .thenReturn(List.of(event(8L), event(14L)));

        SyncEventPageDto result = service.events(userId, 5L, 10);

        assertThat(result.items()).extracting(item -> item.sequenceNo()).containsExactly(8L, 14L);
        assertThat(result.nextCursor()).isEqualTo(20L);
        assertThat(result.latestCursor()).isEqualTo(20L);
        assertThat(result.hasMore()).isFalse();
        assertThat(result.resetRequired()).isFalse();
        verify(eventRepository).findVisibleEvents(eq(userId), eq(5L), eq(20L), any(Pageable.class));
    }

    @Test
    void eventsKeepsPageBoundaryWhenMoreUserEventsExist() {
        UUID userId = UUID.randomUUID();
        when(eventRepository.findVisibleEvents(eq(userId), eq(5L), eq(20L), any(Pageable.class)))
                .thenReturn(List.of(event(8L), event(12L), event(16L)));

        SyncEventPageDto result = service.events(userId, 5L, 2);

        assertThat(result.items()).extracting(item -> item.sequenceNo()).containsExactly(8L, 12L);
        assertThat(result.nextCursor()).isEqualTo(12L);
        assertThat(result.hasMore()).isTrue();
    }

    @Test
    void eventsRequestsResetWhenCursorExpired() {
        UUID userId = UUID.randomUUID();

        SyncEventPageDto result = service.events(userId, 4L, 20);

        assertThat(result.resetRequired()).isTrue();
        assertThat(result.nextCursor()).isEqualTo(20L);
        verify(eventRepository, never()).findVisibleEvents(any(), eq(4L), eq(20L), any(Pageable.class));
    }

    @Test
    void eventsRequestsResetWhenCursorIsAheadOfServer() {
        UUID userId = UUID.randomUUID();

        SyncEventPageDto result = service.events(userId, 21L, 20);

        assertThat(result.resetRequired()).isTrue();
        assertThat(result.nextCursor()).isEqualTo(20L);
        verify(eventRepository, never()).findVisibleEvents(any(), eq(21L), eq(20L), any(Pageable.class));
    }

    private SyncEvent event(long sequenceNo) {
        SyncEvent event = new SyncEvent();
        event.setId(UUID.randomUUID());
        event.setSequenceNo(sequenceNo);
        event.setRecipientUserId(UUID.randomUUID());
        event.setScope(SyncScope.FILES);
        event.setResourceType("FILE_NODE");
        event.setResourceId(UUID.randomUUID().toString());
        event.setAction(SyncAction.UPDATED);
        event.setPayload(Map.of("parentId", UUID.randomUUID().toString()));
        event.setCreatedAt(Instant.now());
        return event;
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
