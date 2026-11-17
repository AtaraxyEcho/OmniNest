package com.omninest.modules.file.domain;

import lombok.AllArgsConstructor;
import lombok.Getter;

/**
 * 文件空间类型。
 */
@Getter
@AllArgsConstructor
public enum SpaceType {
    PERSONAL("PERSONAL"),
    SHARED("SHARED");

    private final String value;

    public static SpaceType fromValue(String value) {
        for (SpaceType type : values()) {
            if (type.value.equalsIgnoreCase(value)) {
                return type;
            }
        }
        throw new IllegalArgumentException("未知的空间类型: " + value);
    }
}
