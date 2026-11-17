package com.omninest.modules.user.controller;

import com.omninest.modules.user.config.InitialSetupProperties;
import java.net.URI;
import java.net.URISyntaxException;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.servlet.view.RedirectView;

/**
 * 将后端安装入口重定向到统一的 Flutter 安装向导。
 *
 * @author OmniNest
 */
@Controller
@RequiredArgsConstructor
public class InitialSetupWebController {
    private static final String SETUP_FRAGMENT = "/#/setup";

    private final InitialSetupProperties properties;

    /**
     * 打开部署人配置的 Flutter Web 安装向导。
     *
     * @return 安装向导重定向视图
     */
    @GetMapping("/setup")
    public RedirectView setup() {
        String webBaseUrl = properties.getWebBaseUrl();
        if (webBaseUrl == null || webBaseUrl.isBlank()) {
            return new RedirectView(SETUP_FRAGMENT);
        }
        String normalizedBaseUrl = validateAndNormalizeBaseUrl(webBaseUrl.trim());
        return new RedirectView(normalizedBaseUrl + SETUP_FRAGMENT);
    }

    private String validateAndNormalizeBaseUrl(String webBaseUrl) {
        try {
            URI uri = new URI(webBaseUrl);
            String scheme = uri.getScheme();
            if (!("http".equalsIgnoreCase(scheme) || "https".equalsIgnoreCase(scheme))
                    || uri.getHost() == null
                    || uri.getUserInfo() != null
                    || uri.getQuery() != null
                    || uri.getFragment() != null) {
                throw new IllegalStateException("安装向导 Web 地址格式不正确");
            }
            return webBaseUrl.endsWith("/")
                    ? webBaseUrl.substring(0, webBaseUrl.length() - 1)
                    : webBaseUrl;
        } catch (URISyntaxException exception) {
            throw new IllegalStateException("安装向导 Web 地址格式不正确", exception);
        }
    }
}
