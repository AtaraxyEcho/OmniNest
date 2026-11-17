package com.omninest.modules.media.domain;

import lombok.AllArgsConstructor;
import lombok.Getter;

/**
 * 资源类型。
 */
@Getter
@AllArgsConstructor
public enum ResourceType {
    VIDEO_ITEM("VIDEO_ITEM"),
    TV_SERIES("TV_SERIES"),
    MOVIE("MOVIE"),
    READER_ITEM("READER_ITEM"),
    PHOTO_ITEM("PHOTO_ITEM"),
    PHOTO_ALBUM("PHOTO_ALBUM"),
    MUSIC_TRACK("MUSIC_TRACK"),
    MUSIC_ALBUM("MUSIC_ALBUM");

    private final String value;

    public static ResourceType fromValue(String value) {
        for (ResourceType type : values()) {
            if (type.value.equalsIgnoreCase(value)) {
                return type;
            }
        }
        throw new IllegalArgumentException("未知的资源类型: " + value);
    }
}
