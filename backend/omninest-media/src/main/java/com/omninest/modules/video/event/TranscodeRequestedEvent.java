package com.omninest.modules.video.event;

import java.util.UUID;

public record TranscodeRequestedEvent(
        UUID taskId,
        UUID videoItemId,
        UUID ownerUserId,
        boolean audioOnly,
        boolean webOptimize
) {
}
