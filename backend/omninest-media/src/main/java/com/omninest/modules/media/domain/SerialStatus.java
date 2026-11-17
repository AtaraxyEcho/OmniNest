package com.omninest.modules.media.domain;

import lombok.AllArgsConstructor;
import lombok.Getter;

/**
 * 连载状态（小说、漫画）。
 */
@Getter
@AllArgsConstructor
public enum SerialStatus {
    UNKNOWN("UNKNOWN"),
    ONGOING("ONGOING"),
    COMPLETED("COMPLETED"),
    HIATUS("HIATUS");

    private final String value;

    public static SerialStatus fromValue(String value) {
        for (SerialStatus status : values()) {
            if (status.value.equalsIgnoreCase(value)) {
                return status;
            }
        }
        throw new IllegalArgumentException("未知的连载状态: " + value);
    }
}
