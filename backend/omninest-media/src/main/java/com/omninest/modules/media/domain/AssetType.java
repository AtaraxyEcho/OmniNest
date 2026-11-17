package com.omninest.modules.media.domain;

import lombok.AllArgsConstructor;
import lombok.Getter;

/**
 * 内容资产类型。
 */
@Getter
@AllArgsConstructor
public enum AssetType {
    POSTER("POSTER"),
    BACKDROP("BACKDROP"),
    SCREENSHOT("SCREENSHOT"),
    PROFILE("PROFILE");

    private final String value;

    public static AssetType fromValue(String value) {
        for (AssetType type : values()) {
            if (type.value.equalsIgnoreCase(value)) {
                return type;
            }
        }
        throw new IllegalArgumentException("未知的资产类型: " + value);
    }
}
