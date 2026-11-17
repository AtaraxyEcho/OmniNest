package com.omninest.modules.file.service;

import com.omninest.modules.file.domain.SpaceType;
import java.util.UUID;

public record DerivedAssetRequest(
        UUID ownerUserId,
        String sourceUrl,
        String resourceType,
        UUID resourceId,
        String assetType,
        String fileName,
        String mimeType,
        SpaceType spaceType
) {
    public DerivedAssetRequest {
        if (spaceType == null) {
            spaceType = SpaceType.PERSONAL;
        }
    }
}
