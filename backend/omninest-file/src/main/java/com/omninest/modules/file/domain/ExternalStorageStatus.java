package com.omninest.modules.file.domain;

import lombok.AllArgsConstructor;
import lombok.Getter;

/**
 * 外部存储状态。
 */
@Getter
@AllArgsConstructor
public enum ExternalStorageStatus {
    ACTIVE("ACTIVE"),
    DISABLED("DISABLED");

    private final String value;

    public static ExternalStorageStatus fromValue(String value) {
        for (ExternalStorageStatus status : values()) {
            if (status.value.equalsIgnoreCase(value)) {
                return status;
            }
        }
        throw new IllegalArgumentException("未知的外部存储状态: " + value);
    }
}
