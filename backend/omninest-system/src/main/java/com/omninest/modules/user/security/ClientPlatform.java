package com.omninest.modules.user.security;

import java.util.Locale;
import java.util.Set;

/**
 * 客户端平台标识归一化。
 *
 * <p>平台标识来自请求头，同时参与同平台单设备互斥判定和 Redis 会话键拼接。不做归一化时，
 * 客户端只要改写大小写或塞入随机串就能绕开同平台互斥，并把任意长字符串写进键空间；
 * 数据库列又只保留 32 字符，登录与刷新两侧算出的键会不一致。归一化后未知值统一落到
 * {@code native}，与缺省请求头同一档，无法再制造新的互斥桶。</p>
 *
 * @author OmniNest
 */
public final class ClientPlatform {

    /** 允许的客户端平台标识（小写）。 */
    private static final Set<String> KNOWN_PLATFORMS = Set.of(
            "web", "android", "ios", "windows", "macos", "linux", "native");

    /** 未识别平台归入的档位，与请求头缺省值一致。 */
    public static final String DEFAULT_PLATFORM = "native";

    private ClientPlatform() {
    }

    /**
     * 将请求头传入的平台标识归一化为固定档位。
     *
     * @param rawPlatform 原始请求头值，可空
     * @return 白名单内的小写平台标识，未识别时返回 {@code native}
     */
    public static String normalize(String rawPlatform) {
        if (rawPlatform == null) {
            return DEFAULT_PLATFORM;
        }
        String value = rawPlatform.trim().toLowerCase(Locale.ROOT);
        return KNOWN_PLATFORMS.contains(value) ? value : DEFAULT_PLATFORM;
    }
}
