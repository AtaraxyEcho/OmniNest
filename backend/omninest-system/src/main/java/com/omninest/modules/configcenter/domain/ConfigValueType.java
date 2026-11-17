package com.omninest.modules.configcenter.domain;

import lombok.AllArgsConstructor;
import lombok.Getter;

/**
 * 配置值类型。
 */
@Getter
@AllArgsConstructor
public enum ConfigValueType {
    STRING("STRING"),
    NUMBER("NUMBER"),
    BOOLEAN("BOOLEAN"),
    JSON("JSON");

    private final String value;

    public static ConfigValueType fromValue(String value) {
        for (ConfigValueType type : values()) {
            if (type.value.equalsIgnoreCase(value)) {
                return type;
            }
        }
        throw new IllegalArgumentException("未知的配置值类型: " + value);
    }
}
