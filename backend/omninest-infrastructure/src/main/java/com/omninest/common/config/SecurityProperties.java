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

    private String contentSecurityPolicy = "default-src 'self'; "
            + "script-src 'self' 'unsafe-inline' 'wasm-unsafe-eval'; "
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
