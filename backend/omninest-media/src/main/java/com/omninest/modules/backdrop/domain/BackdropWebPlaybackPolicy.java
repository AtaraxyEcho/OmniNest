package com.omninest.modules.backdrop.domain;

import java.util.Locale;
import java.util.Set;

/**
 * 背景视频在 Web 客户端的可解码判定。
 *
 * <p>仅用于在用户切换壁纸前给出提示，不参与权限、配额或安全判断。</p>
 *
 * @author OmniNest
 */
public final class BackdropWebPlaybackPolicy {

    /** Chromium、Firefox 与 Edge 稳定支持的编码；HEVC 只在 Safari 等少数环境可用，不视为通用可播。 */
    private static final Set<String> WEB_SUPPORTED_CODECS = Set.of("h264", "av1", "vp8", "vp9", "theora");

    private BackdropWebPlaybackPolicy() {
    }

    /**
     * 判断编码名在 Web 客户端是否可解码。
     *
     * @param codecName ffprobe 输出的编码名，可为空
     * @return 编码未知或探测失败时按可播处理，避免误报
     */
    public static boolean isWebPlayable(String codecName) {
        if (codecName == null || codecName.isBlank()) {
            return true;
        }
        return WEB_SUPPORTED_CODECS.contains(codecName.trim().toLowerCase(Locale.ROOT));
    }
}
