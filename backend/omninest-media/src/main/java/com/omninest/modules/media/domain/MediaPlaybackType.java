package com.omninest.modules.media.domain;

import java.util.Locale;

/**
 * 统一媒体进度支持的媒体类型。
 *
 * @author OmniNest
 */
public enum MediaPlaybackType {
    VIDEO("video"),
    MUSIC("music");

    private final String value;

    MediaPlaybackType(String value) {
        this.value = value;
    }

    /**
     * 获取数据库与 API 使用的稳定值。
     *
     * @return 媒体类型值
     */
    public String value() {
        return value;
    }

    /**
     * 将外部值转换为白名单媒体类型。
     *
     * @param value 外部媒体类型
     * @return 媒体类型
     */
    public static MediaPlaybackType fromValue(String value) {
        String normalized = value == null ? "" : value.trim().toLowerCase(Locale.ROOT);
        for (MediaPlaybackType type : values()) {
            if (type.value.equals(normalized)) {
                return type;
            }
        }
        throw new IllegalArgumentException("不支持的媒体播放类型: " + value);
    }
}
