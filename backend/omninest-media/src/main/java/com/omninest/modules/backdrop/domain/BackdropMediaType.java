package com.omninest.modules.backdrop.domain;

import java.util.Arrays;

/**
 * 背景素材媒体类型。
 *
 * <p>取值与前端 AppBackdropMediaType 的序列化值保持一致。</p>
 *
 * @author OmniNest
 */
public enum BackdropMediaType {
    IMAGE("image"),

    GIF("gif"),

    VIDEO("video");

    private final String value;

    BackdropMediaType(String value) {
        this.value = value;
    }

    public String getValue() {
        return value;
    }

    /**
     * 按持久化值解析媒体类型。
     *
     * @param value 持久化值
     * @return 匹配的媒体类型，未知值回落为 IMAGE
     */
    public static BackdropMediaType fromValue(String value) {
        return Arrays.stream(values())
                .filter(type -> type.value.equals(value))
                .findFirst()
                .orElse(IMAGE);
    }
}
