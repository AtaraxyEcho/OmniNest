package com.omninest.modules.user.service;

import com.omninest.modules.user.config.InitialSetupProperties;
import java.net.URI;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

/**
 * 对外 Web 基址解析服务。
 *
 * <p>分享等需要跨设备打开的链接必须指向部署者配置的对外 Web 地址
 * （omninest.setup.web-base-url），而非客户端本机地址；未配置或配置
 * 非法时返回空，由客户端按平台语义回退并提示风险。</p>
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class WebShareBaseUrlService {
    private final InitialSetupProperties setupProperties;

    /**
     * 解析归一化后的对外 Web 基址。
     *
     * @return 去除尾部斜杠的绝对 http(s) 地址；未配置或非法时返回 null
     */
    public String resolveShareBaseUrl() {
        String raw = setupProperties.getWebBaseUrl();
        if (raw == null || raw.isBlank()) {
            return null;
        }
        try {
            URI uri = URI.create(raw.trim());
            String scheme = uri.getScheme();
            if (uri.getHost() == null
                    || (!"http".equalsIgnoreCase(scheme) && !"https".equalsIgnoreCase(scheme))) {
                return null;
            }
            String normalized = uri.toString();
            return normalized.endsWith("/")
                    ? normalized.substring(0, normalized.length() - 1)
                    : normalized;
        } catch (IllegalArgumentException exception) {
            return null;
        }
    }
}
