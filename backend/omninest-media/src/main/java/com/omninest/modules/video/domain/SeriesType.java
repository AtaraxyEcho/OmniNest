package com.omninest.modules.video.domain;

import lombok.AllArgsConstructor;
import lombok.Getter;

/**
 * 系列类型。
 */
@Getter
@AllArgsConstructor
public enum SeriesType {
    TV("TV"),
    ANIME("ANIME"),
    DOCUMENTARY("DOCUMENTARY");

    private final String value;

    public static SeriesType fromValue(String value) {
        for (SeriesType type : values()) {
            if (type.value.equalsIgnoreCase(value)) {
                return type;
            }
        }
        throw new IllegalArgumentException("未知的系列类型: " + value);
    }
}
