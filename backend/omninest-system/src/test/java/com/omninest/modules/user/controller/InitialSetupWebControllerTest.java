package com.omninest.modules.user.controller;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.omninest.modules.user.config.InitialSetupProperties;
import org.junit.jupiter.api.Test;

/**
 * 首次安装 Web 入口测试。
 *
 * @author OmniNest
 */
class InitialSetupWebControllerTest {

    @Test
    void redirectsToSameOriginSetupWhenWebBaseUrlIsMissing() {
        InitialSetupProperties properties = new InitialSetupProperties();
        InitialSetupWebController controller = new InitialSetupWebController(properties);

        assertThat(controller.setup().getUrl()).isEqualTo("/#/setup");
    }

    @Test
    void redirectsToConfiguredFlutterWebOrigin() {
        InitialSetupProperties properties = new InitialSetupProperties();
        properties.setWebBaseUrl("https://nest.example.com/");
        InitialSetupWebController controller = new InitialSetupWebController(properties);

        assertThat(controller.setup().getUrl()).isEqualTo("https://nest.example.com/#/setup");
    }

    @Test
    void rejectsConfiguredAddressWithCredentials() {
        InitialSetupProperties properties = new InitialSetupProperties();
        properties.setWebBaseUrl("https://user:password@nest.example.com");
        InitialSetupWebController controller = new InitialSetupWebController(properties);

        assertThatThrownBy(controller::setup)
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("格式不正确");
    }
}
