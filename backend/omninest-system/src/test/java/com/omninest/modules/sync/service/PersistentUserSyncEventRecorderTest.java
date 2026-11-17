package com.omninest.modules.sync.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;

import com.omninest.common.error.BusinessException;
import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncEventCommand;
import com.omninest.common.sync.SyncScope;
import com.omninest.modules.sync.domain.SyncEvent;
import com.omninest.modules.sync.repository.SyncEventRepository;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

/**
 * 持久化同步事件记录器单元测试。
 *
 * @author OmniNest
 */
class PersistentUserSyncEventRecorderTest {

    private final SyncEventRepository repository = mock(SyncEventRepository.class);
    private final PersistentUserSyncEventRecorder recorder = new PersistentUserSyncEventRecorder(repository);

    @Test
    void recordMapsCommandToPendingEvent() {
        UUID userId = UUID.randomUUID();
        SyncEventCommand command = new SyncEventCommand(
                userId,
                SyncScope.FILES,
                " FILE_NODE ",
                " node-1 ",
                SyncAction.UPDATED,
                7L,
                Map.of("parentId", "folder-1")
        );

        UUID eventId = recorder.record(command);

        ArgumentCaptor<SyncEvent> captor = ArgumentCaptor.forClass(SyncEvent.class);
        verify(repository).save(captor.capture());
        SyncEvent event = captor.getValue();
        assertThat(eventId).isEqualTo(event.getId());
        assertThat(event.getRecipientUserId()).isEqualTo(userId);
        assertThat(event.getScope()).isEqualTo(SyncScope.FILES);
        assertThat(event.getResourceType()).isEqualTo("FILE_NODE");
        assertThat(event.getResourceId()).isEqualTo("node-1");
        assertThat(event.getAction()).isEqualTo(SyncAction.UPDATED);
        assertThat(event.getResourceVersion()).isEqualTo(7L);
        assertThat(event.getPayload()).containsEntry("parentId", "folder-1");
        assertThat(event.getPublishStatus()).isEqualTo("PENDING");
    }

    @Test
    void recordRejectsIncompleteCommand() {
        SyncEventCommand command = new SyncEventCommand(
                null,
                SyncScope.FILES,
                "FILE_NODE",
                null,
                SyncAction.UPDATED,
                null,
                Map.of()
        );

        assertThatThrownBy(() -> recorder.record(command))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("参数不完整");
    }

    @Test
    void recordRequiresCallerTransaction() throws NoSuchMethodException {
        Transactional transactional = PersistentUserSyncEventRecorder.class
                .getMethod("record", SyncEventCommand.class)
                .getAnnotation(Transactional.class);

        assertThat(transactional).isNotNull();
        assertThat(transactional.propagation()).isEqualTo(Propagation.MANDATORY);
    }
}
