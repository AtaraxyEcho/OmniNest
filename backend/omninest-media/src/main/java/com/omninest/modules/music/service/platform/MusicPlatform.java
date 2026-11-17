package com.omninest.modules.music.service.platform;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import java.util.Locale;

/**
 * 支持的在线音乐平台。
 *
 * @author OmniNest
 */
public enum MusicPlatform {
    NETEASE("netease", "网易云音乐");

    private final String apiValue;
    private final String displayName;

    MusicPlatform(String apiValue, String displayName) {
        this.apiValue = apiValue;
        this.displayName = displayName;
    }

    /**
     * 获取 API 标识。
     *
     * @return API 标识
     */
    public String apiValue() {
        return apiValue;
    }

    /**
     * 获取平台显示名称。
     *
     * @return 显示名称
     */
    public String displayName() {
        return displayName;
    }

    /**
     * 将 API 参数转换为平台枚举。
     *
     * @param value API 参数
     * @return 平台枚举
     * @throws BusinessException 平台不受支持时抛出
     */
    public static MusicPlatform fromApiValue(String value) {
        String normalized = value == null ? "" : value.trim().toLowerCase(Locale.ROOT);
        for (MusicPlatform platform : values()) {
            if (platform.apiValue.equals(normalized)) {
                return platform;
            }
        }
        throw new BusinessException(ErrorCode.BAD_REQUEST, "不支持的音乐平台: " + value);
    }
}
