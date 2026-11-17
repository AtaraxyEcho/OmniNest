package com.omninest.modules.video.domain;

import lombok.AllArgsConstructor;
import lombok.Getter;

/**
 * 字幕/音轨类型。
 */
@Getter
@AllArgsConstructor
public enum TrackKind {
    SUBTITLE("SUBTITLE"),
    CAPTION("CAPTION"),
    EXTERNAL("EXTERNAL");

    private final String value;

    public static TrackKind fromValue(String value) {
        for (TrackKind kind : values()) {
            if (kind.value.equalsIgnoreCase(value)) {
                return kind;
            }
        }
        throw new IllegalArgumentException("未知的轨道类型: " + value);
    }
}
