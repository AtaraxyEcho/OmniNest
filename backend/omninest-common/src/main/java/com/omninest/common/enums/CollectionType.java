package com.omninest.common.enums;

import lombok.AllArgsConstructor;
import lombok.Getter;

/**
 * 合集类型。
 */
@Getter
@AllArgsConstructor
public enum CollectionType {
    MANUAL("MANUAL"),
    WATCHLIST("WATCHLIST");

    private final String value;

    public static CollectionType fromValue(String value) {
        for (CollectionType type : values()) {
            if (type.value.equalsIgnoreCase(value)) {
                return type;
            }
        }
        throw new IllegalArgumentException("未知的合集类型: " + value);
    }
}
