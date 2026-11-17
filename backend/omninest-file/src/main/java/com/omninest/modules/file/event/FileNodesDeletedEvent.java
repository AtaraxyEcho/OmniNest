package com.omninest.modules.file.event;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

public record FileNodesDeletedEvent(
        UUID ownerUserId,
        List<UUID> fileNodeIds,
        Instant occurredAt
) {
}
