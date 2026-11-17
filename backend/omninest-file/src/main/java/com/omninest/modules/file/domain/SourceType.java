package com.omninest.modules.file.domain;

import lombok.AllArgsConstructor;
import lombok.Getter;

/**
 * 文件来源类型。
 *
 * @author OmniNest
 */
@Getter
@AllArgsConstructor
public enum SourceType {
    LOCAL("LOCAL"),
    LOCAL_FILESYSTEM("LOCAL_FILESYSTEM"),
    RCLONE("RCLONE"),
    SHARE("SHARE");

    private final String value;

    public static SourceType fromValue(String value) {
        for (SourceType type : values()) {
            if (type.value.equalsIgnoreCase(value)) {
                return type;
            }
        }
        throw new IllegalArgumentException("未知的来源类型: " + value);
    }
}
