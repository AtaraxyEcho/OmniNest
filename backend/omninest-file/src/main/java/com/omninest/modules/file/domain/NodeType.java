package com.omninest.modules.file.domain;

import lombok.AllArgsConstructor;
import lombok.Getter;

/**
 * 文件节点类型。
 */
@Getter
@AllArgsConstructor
public enum NodeType {
    FILE("FILE"),
    FOLDER("FOLDER");

    private final String value;

    public static NodeType fromValue(String value) {
        for (NodeType type : values()) {
            if (type.value.equalsIgnoreCase(value)) {
                return type;
            }
        }
        throw new IllegalArgumentException("未知的节点类型: " + value);
    }
}
