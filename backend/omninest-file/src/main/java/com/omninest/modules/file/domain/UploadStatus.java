package com.omninest.modules.file.domain;

import lombok.AllArgsConstructor;
import lombok.Getter;

/**
 * 上传会话状态。
 */
@Getter
@AllArgsConstructor
public enum UploadStatus {
    PENDING("PENDING"),
    CREATED("CREATED"),
    UPLOADING("UPLOADING"),
    FINALIZING("FINALIZING"),
    SCANNING("SCANNING"),
    COMPLETED("COMPLETED"),
    CANCELLED("CANCELLED"),
    REJECTED("REJECTED"),
    EXPIRED("EXPIRED");

    private final String value;

    public static UploadStatus fromValue(String value) {
        for (UploadStatus status : values()) {
            if (status.value.equalsIgnoreCase(value)) {
                return status;
            }
        }
        throw new IllegalArgumentException("未知的上传状态: " + value);
    }
}
