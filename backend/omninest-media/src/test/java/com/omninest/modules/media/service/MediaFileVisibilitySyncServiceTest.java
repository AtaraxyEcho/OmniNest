package com.omninest.modules.media.service;

import com.omninest.modules.file.event.FileNodesRestoredEvent;
import com.omninest.modules.file.event.FileNodesSoftDeletedEvent;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;

/**
 * 文件可见性同步失效编排测试。
 *
 * @author OmniNest
 */
class MediaFileVisibilitySyncServiceTest {

    private final MediaFileVisibilitySyncParticipant firstParticipant = Mockito.mock(
            MediaFileVisibilitySyncParticipant.class
    );
    private final MediaFileVisibilitySyncParticipant secondParticipant = Mockito.mock(
            MediaFileVisibilitySyncParticipant.class
    );
    private final MediaFileVisibilitySyncService service = new MediaFileVisibilitySyncService(
            List.of(firstParticipant, secondParticipant)
    );

    @Test
    void handleRestoredDelegatesToAllParticipants() {
        List<UUID> fileNodeIds = List.of(UUID.randomUUID());

        service.handleRestored(new FileNodesRestoredEvent(
                UUID.randomUUID(),
                fileNodeIds,
                Instant.now()
        ));

        Mockito.verify(firstParticipant).invalidateFileVisibility(fileNodeIds);
        Mockito.verify(secondParticipant).invalidateFileVisibility(fileNodeIds);
    }

    @Test
    void handleSoftDeletedDelegatesToAllParticipants() {
        List<UUID> fileNodeIds = List.of(UUID.randomUUID());

        service.handleSoftDeleted(new FileNodesSoftDeletedEvent(
                UUID.randomUUID(),
                fileNodeIds,
                Instant.now()
        ));

        Mockito.verify(firstParticipant).invalidateFileVisibility(fileNodeIds);
        Mockito.verify(secondParticipant).invalidateFileVisibility(fileNodeIds);
    }
}
