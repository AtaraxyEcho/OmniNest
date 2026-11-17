package com.omninest.common.storage;

public record ObjectStorageCompletedPart(
        int partNumber,
        String eTag
) {
}
