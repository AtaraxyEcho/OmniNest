package com.omninest.modules.music.domain;

import lombok.AllArgsConstructor;
import lombok.Getter;

/**
 * 播放列表类型。
 */
@Getter
@AllArgsConstructor
public enum PlaylistType {
    CUSTOM("CUSTOM");

    private final String value;

    public static PlaylistType fromValue(String value) {
        for (PlaylistType type : values()) {
            if (type.value.equalsIgnoreCase(value)) {
                return type;
            }
        }
        throw new IllegalArgumentException("未知的播放列表类型: " + value);
    }
}
