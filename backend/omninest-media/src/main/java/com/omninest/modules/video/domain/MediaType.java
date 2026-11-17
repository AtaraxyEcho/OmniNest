package com.omninest.modules.video.domain;

import lombok.AllArgsConstructor;
import lombok.Getter;

/**
 * 媒体类型。
 */
@Getter
@AllArgsConstructor
public enum MediaType {
    MOVIE("MOVIE"),
    EPISODE("EPISODE");

    private final String value;

    public static MediaType fromValue(String value) {
        for (MediaType type : values()) {
            if (type.value.equalsIgnoreCase(value)) {
                return type;
            }
        }
        throw new IllegalArgumentException("未知的媒体类型: " + value);
    }
}
