package com.omninest.modules.video.domain;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import java.util.Locale;

/**
 * 本地媒体库可见性。
 *
 * @author OmniNest
 */
public enum MediaLibraryVisibility {
    PRIVATE,
    SELECTED_USERS,
    ALL_MEMBERS;

    /** 将接口值转换为受控枚举。 */
    public static MediaLibraryVisibility from(String value) {
        if (value == null || value.isBlank()) {
            return PRIVATE;
        }
        try {
            return valueOf(value.trim().toUpperCase(Locale.ROOT));
        } catch (IllegalArgumentException exception) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "媒体库可见性不合法");
        }
    }
}
