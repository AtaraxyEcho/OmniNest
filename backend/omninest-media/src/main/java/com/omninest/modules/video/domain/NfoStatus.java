package com.omninest.modules.video.domain;

import lombok.AllArgsConstructor;
import lombok.Getter;

/**
 * NFO 导出状态。
 *
 * <p>与 {@code media_video_items.nfo_status}、{@code media_nfo_exports.status}
 * 的 CHECK 约束保持一致。</p>
 */
@Getter
@AllArgsConstructor
public enum NfoStatus {
    PENDING("PENDING"),
    GENERATED("GENERATED"),
    FAILED("FAILED"),
    DISABLED("DISABLED");

    private final String value;

    public static NfoStatus fromValue(String value) {
        for (NfoStatus status : values()) {
            if (status.value.equalsIgnoreCase(value)) {
                return status;
            }
        }
        throw new IllegalArgumentException("未知的 NFO 状态: " + value);
    }
}
