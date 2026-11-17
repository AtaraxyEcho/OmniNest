package com.omninest.modules.file.domain;

import lombok.AllArgsConstructor;
import lombok.Getter;

/**
 * 对象存储类型。
 */
@Getter
@AllArgsConstructor
public enum StorageClass {
    STANDARD("STANDARD"),
    GLACIER("GLACIER");

    private final String value;

    public static StorageClass fromValue(String value) {
        for (StorageClass cls : values()) {
            if (cls.value.equalsIgnoreCase(value)) {
                return cls;
            }
        }
        throw new IllegalArgumentException("未知的存储类型: " + value);
    }
}
