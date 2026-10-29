package com.omninest.common.security;

import java.util.Locale;
import java.util.Set;

/**
 * 浏览器可执行内容的内联策略。
 *
 * <p>内容端点既走 MinIO 预签名地址，也走本地文件的令牌直读地址；只要这些地址以
 * 应用同源内联返回 {@code text/html} 或 {@code image/svg+xml}，就构成存储型 XSS 面。
 * 判定集中在此，任何一条签发路径漏判都会留口子。</p>
 *
 * <p>放在 common 而非业务模块：签发方横跨 File Provider 与各业务模块的公开内容控制器，
 * 控制器不得跨模块依赖 service 包。</p>
 *
 * @author OmniNest
 */
public final class InlineContentPolicy {

    /**
     * 浏览器会直接执行的类型：命中即必须按附件下发并覆盖为不可执行类型。
     */
    private static final Set<String> INLINE_EXECUTABLE_TYPES = Set.of(
            "text/html",
            "application/xhtml+xml",
            "image/svg+xml",
            "application/xml",
            "text/xml",
            "application/javascript",
            "text/javascript"
    );

    /**
     * 不可执行兜底类型：拒绝内联执行时统一按字节流下发。
     */
    public static final String FALLBACK_MIME_TYPE = "application/octet-stream";

    private InlineContentPolicy() {
    }

    /**
     * 判断 MIME 类型是否可被浏览器当作脚本或标记执行。
     *
     * @param mimeType 节点登记的 MIME 类型，可为空
     * @return 可执行时返回 true
     */
    public static boolean isExecutable(String mimeType) {
        if (mimeType == null || mimeType.isBlank()) {
            return false;
        }
        return INLINE_EXECUTABLE_TYPES.contains(mimeType.trim().toLowerCase(Locale.ROOT));
    }
}
