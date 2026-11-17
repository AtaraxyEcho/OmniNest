package com.omninest.modules.file.domain;

import lombok.AllArgsConstructor;
import lombok.Getter;

/**
 * 加密状态。
 */
@Getter
@AllArgsConstructor
public enum EncryptionStatus {
    SERVER_SIDE("SERVER_SIDE"),
    CLIENT_SIDE("CLIENT_SIDE"),
    NONE("NONE");

    private final String value;

    public static EncryptionStatus fromValue(String value) {
        for (EncryptionStatus status : values()) {
            if (status.value.equalsIgnoreCase(value)) {
                return status;
            }
        }
        throw new IllegalArgumentException("未知的加密状态: " + value);
    }
}
