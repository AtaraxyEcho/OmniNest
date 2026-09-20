package com.omninest.common.security;

import java.util.List;

/**
 * 提供浏览器 Cookie 和跨域访问安全策略。
 *
 * @author OmniNest
 */
public interface BrowserSecurityPolicy {

    /**
     * 返回刷新令牌 Cookie 是否仅通过安全连接传输。
     *
     * @return 启用安全传输时返回 true
     */
    boolean refreshCookieSecure();

    /**
     * 返回刷新令牌 Cookie 的 SameSite 属性（Strict/Lax/None）。
     * 前端站点与 API 跨站点部署时，Strict 会导致浏览器拒绝随请求
     * 发送 Cookie，会话刷新在页面刷新后必然失败；此时应配置 None
     *（并强制 Secure，要求 HTTPS）。
     *
     * @return SameSite 属性值，缺省 Strict
     */
    default String refreshCookieSameSite() {
        return "Strict";
    }

    /**
     * 返回允许建立浏览器连接的来源列表。
     *
     * @return 允许的来源列表
     */
    List<String> allowedOrigins();
}
