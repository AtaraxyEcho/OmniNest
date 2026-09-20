package com.omninest.modules.user.service;

import static org.assertj.core.api.Assertions.assertThat;

import com.omninest.modules.user.config.InitialSetupProperties;
import org.junit.jupiter.api.Test;

/**
 * {@link WebShareBaseUrlService} 单元测试。
 *
 * @author OmniNest
 */
class WebShareBaseUrlServiceTest {

    private WebShareBaseUrlService serviceWith(String webBaseUrl) {
        InitialSetupProperties properties = new InitialSetupProperties();
        properties.setWebBaseUrl(webBaseUrl);
        return new WebShareBaseUrlService(properties);
    }

    @Test
    void resolvesNormalizedAbsoluteUrl() {
        assertThat(serviceWith("https://media.example.com/").resolveShareBaseUrl())
                .isEqualTo("https://media.example.com");
        assertThat(serviceWith("http://192.168.1.10:3000").resolveShareBaseUrl())
                .isEqualTo("http://192.168.1.10:3000");
    }

    @Test
    void blankOrUnconfiguredReturnsNull() {
        assertThat(serviceWith(null).resolveShareBaseUrl()).isNull();
        assertThat(serviceWith("   ").resolveShareBaseUrl()).isNull();
    }

    @Test
    void invalidSchemeOrRelativeUrlReturnsNull() {
        assertThat(serviceWith("ftp://media.example.com").resolveShareBaseUrl()).isNull();
        assertThat(serviceWith("/relative/path").resolveShareBaseUrl()).isNull();
        assertThat(serviceWith("not a url").resolveShareBaseUrl()).isNull();
    }
}
