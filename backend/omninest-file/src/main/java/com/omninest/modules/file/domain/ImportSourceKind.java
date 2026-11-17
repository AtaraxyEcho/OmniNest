package com.omninest.modules.file.domain;

import lombok.AllArgsConstructor;
import lombok.Getter;

/**
 * 外部存储导入源类型。
 *
 * @author OmniNest
 */
@Getter
@AllArgsConstructor
public enum ImportSourceKind {
    FILE("FILE"),
    DIRECTORY("DIRECTORY");

    private final String value;

    /**
     * 根据持久化值解析导入源类型。
     *
     * @param value 持久化值
     * @return 导入源类型
     */
    public static ImportSourceKind fromValue(String value) {
        for (ImportSourceKind kind : values()) {
            if (kind.value.equalsIgnoreCase(value)) {
                return kind;
            }
        }
        throw new IllegalArgumentException("未知的导入源类型: " + value);
    }
}
