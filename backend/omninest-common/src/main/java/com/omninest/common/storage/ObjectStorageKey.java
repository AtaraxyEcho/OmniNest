package com.omninest.common.storage;

public record ObjectStorageKey(String bucket, String objectKey) {
    public ObjectStorageKey {
        if (bucket == null || bucket.isBlank()) {
            throw new IllegalArgumentException("bucket is required");
        }
        if (objectKey == null || objectKey.isBlank()) {
            throw new IllegalArgumentException("objectKey is required");
        }
    }
}
