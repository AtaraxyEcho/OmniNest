package com.omninest.common.config;

import com.omninest.common.security.AuthenticationTokenPolicy;
import com.omninest.common.security.BrowserSecurityPolicy;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * 面向浏览器访问的安全与跨域配置项。
 *
 * @author OmniNest
 */
@Data
@ConfigurationProperties(prefix = "omninest.security")
public class SecurityProperties implements AuthenticationTokenPolicy, BrowserSecurityPolicy {
    private String jwtSecret = "change-me-omninest-local-jwt-secret-at-least-32-bytes";

    /**
     * 是否显式豁免“公开默认 JWT secret”的启动拦截。
     * 仅限本机回环调试；生产 profile 无论该值如何都拒绝默认 secret。
     */
    private boolean allowInsecureLocalSecret = false;

    private String credentialEncryptionKey = "";

    private int credentialEncryptionKeyVersion = 1;

    private Duration accessTokenTtl = Duration.ofMinutes(30);

    private Duration refreshTokenTtl = Duration.ofDays(30);

    private Duration refreshSessionMaxLifetime = Duration.ofDays(90);

    private boolean refreshCookieSecure = false;

    private String refreshCookieSameSite = "Strict";

    private boolean registrationEnabled = false;

    private List<String> trustedProxies = new ArrayList<>();

    private boolean allowCredentials = true;

    private List<String> allowedOrigins = new ArrayList<>(List.of(
            "http://localhost:3000",
            "http://127.0.0.1:3000"
    ));

    /**
     * 浏览器 CSP。script-src 禁止 unsafe-inline（启动脚本已外置到 web/js）。
     * style-src 保留 unsafe-inline：Flutter Web 引擎/CanvasKit 运行时会注入内联 style，
     * 去掉会导致文本编辑与渲染层样式失效；待 Flutter 提供 nonce/hash 方案后再收紧。
     * worker-src 必须放行 blob：pdfrx 的 pdfium 客户端从 blob URL 创建 Worker，
     * 未显式声明时会回落到 script-src 并被拦截，表现为 PDF 预览区一片空白且不报错。
     */
    private String contentSecurityPolicy = "default-src 'self'; "
            + "script-src 'self' 'wasm-unsafe-eval'; "
            + "worker-src 'self' blob:; "
            + "style-src 'self' 'unsafe-inline'; "
            + "font-src 'self' data:; "
            + "img-src 'self' data: blob: http: https:; "
            + "media-src 'self' blob: http: https:; "
            + "connect-src 'self' http: https: ws: wss:; "
            + "frame-src 'self' blob:; "
            + "object-src 'none'; "
            + "base-uri 'self'; "
            + "frame-ancestors 'self'";

    private String permissionsPolicy = "camera=(), microphone=(), geolocation=(), payment=()";

    @Override
    public Duration accessTokenTtl() {
        return accessTokenTtl;
    }

    @Override
    public Duration refreshTokenTtl() {
        return refreshTokenTtl;
    }

    @Override
    public Duration refreshSessionMaxLifetime() {
        return refreshSessionMaxLifetime;
    }

    @Override
    public boolean refreshCookieSecure() {
        return refreshCookieSecure;
    }

    @Override
    public String refreshCookieSameSite() {
        return refreshCookieSameSite;
    }

    @Override
    public List<String> allowedOrigins() {
        return List.copyOf(allowedOrigins);
    }
}
