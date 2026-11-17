package com.omninest.common.storage;

import java.time.Instant;

/**
 * 对象存储清单中的单个对象摘要。
 *
 * @param objectKey 对象键
 * @param sizeBytes 对象字节数
 * @param lastModified 最后修改时间
 * @author OmniNest
 */
public record ObjectStorageObject(
        String objectKey,
        long sizeBytes,
        Instant lastModified
) {
    public ObjectStorageObject {
        if (objectKey == null || objectKey.isBlank()) {
            throw new IllegalArgumentException("objectKey is required");
        }
        if (sizeBytes < 0) {
            throw new IllegalArgumentException("sizeBytes must not be negative");
        }
        if (lastModified == null) {
            throw new IllegalArgumentException("lastModified is required");
        }
    }
}
