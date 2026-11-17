package com.omninest.modules.media.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;

import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncEventCommand;
import com.omninest.common.sync.SyncScope;
import com.omninest.common.sync.UserSyncEventRecorder;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

/**
 * 媒体同步事件协议适配服务测试。
 *
 * @author OmniNest
 */
class MediaSyncEventServiceTest {

    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");

    private final UserSyncEventRecorder syncEventRecorder = mock(UserSyncEventRecorder.class);
    private final MediaSyncEventService service = new MediaSyncEventService(syncEventRecorder);

    @Test
    void recordPreservesResourceEventContract() {
        service.record(
                OWNER_ID,
                SyncScope.MUSIC,
                "track",
                "track-1",
                SyncAction.UPDATED,
                7L,
                Map.of("source", "local")
        );

        ArgumentCaptor<SyncEventCommand> commandCaptor = ArgumentCaptor.forClass(SyncEventCommand.class);
        verify(syncEventRecorder).record(commandCaptor.capture());
        SyncEventCommand command = commandCaptor.getValue();
        assertThat(command.recipientUserId()).isEqualTo(OWNER_ID);
        assertThat(command.scope()).isEqualTo(SyncScope.MUSIC);
        assertThat(command.resourceType()).isEqualTo("track");
        assertThat(command.resourceId()).isEqualTo("track-1");
        assertThat(command.action()).isEqualTo(SyncAction.UPDATED);
        assertThat(command.resourceVersion()).isEqualTo(7L);
        assertThat(command.hints()).containsEntry("source", "local");
    }

    @Test
    void invalidateCreatesScopeLevelInvalidation() {
        service.invalidate(
                OWNER_ID,
                SyncScope.PHOTOS,
                "library",
                Map.of("reason", "scan_completed")
        );

        ArgumentCaptor<SyncEventCommand> commandCaptor = ArgumentCaptor.forClass(SyncEventCommand.class);
        verify(syncEventRecorder).record(commandCaptor.capture());
        SyncEventCommand command = commandCaptor.getValue();
        assertThat(command.scope()).isEqualTo(SyncScope.PHOTOS);
        assertThat(command.resourceType()).isEqualTo("library");
        assertThat(command.resourceId()).isNull();
        assertThat(command.action()).isEqualTo(SyncAction.INVALIDATED);
        assertThat(command.resourceVersion()).isNull();
        assertThat(command.hints()).containsEntry("reason", "scan_completed");
    }
}
