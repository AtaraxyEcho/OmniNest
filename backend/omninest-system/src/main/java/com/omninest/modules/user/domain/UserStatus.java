package com.omninest.modules.user.domain;

import lombok.AllArgsConstructor;
import lombok.Getter;

/**
 * 用户状态。
 */
@Getter
@AllArgsConstructor
public enum UserStatus {
    ACTIVE("ACTIVE"),
    DISABLED("DISABLED");

    private final String value;

    public static UserStatus fromValue(String value) {
        for (UserStatus status : values()) {
            if (status.value.equalsIgnoreCase(value)) {
                return status;
            }
        }
        throw new IllegalArgumentException("未知的用户状态: " + value);
    }
}
