package com.omninest.modules.reader.domain;

/**
 * 阅读条目类型枚举。
 */
public enum ReaderItemType {
    EPUB("EPUB"),
    TXT("TXT"),
    CBZ("CBZ"),
    ZIP("ZIP"),
    PDF("PDF");

    private final String value;

    ReaderItemType(String value) {
        this.value = value;
    }

    public String getValue() {
        return value;
    }

    /**
     * 从字符串值解析枚举，忽略大小写。
     */
    public static ReaderItemType fromValue(String value) {
        for (ReaderItemType type : values()) {
            if (type.value.equalsIgnoreCase(value)) {
                return type;
            }
        }
        throw new IllegalArgumentException("未知的阅读条目类型: " + value);
    }

    /**
     * 判断给定值是否为有效的阅读条目类型。
     */
    public static boolean isValid(String value) {
        for (ReaderItemType type : values()) {
            if (type.value.equalsIgnoreCase(value)) {
                return true;
            }
        }
        return false;
    }
}
