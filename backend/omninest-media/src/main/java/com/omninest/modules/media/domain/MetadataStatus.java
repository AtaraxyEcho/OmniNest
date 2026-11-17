package com.omninest.modules.media.domain;

import lombok.AllArgsConstructor;
import lombok.Getter;

/**
 * 元数据状态。
 */
@Getter
@AllArgsConstructor
public enum MetadataStatus {
    PENDING("PENDING"),
    MATCHED("MATCHED"),
    FAILED("FAILED"),
    MANUAL("MANUAL");

    private final String value;

    public static MetadataStatus fromValue(String value) {
        for (MetadataStatus status : values()) {
            if (status.value.equalsIgnoreCase(value)) {
                return status;
            }
        }
        throw new IllegalArgumentException("未知的元数据状态: " + value);
    }
}
