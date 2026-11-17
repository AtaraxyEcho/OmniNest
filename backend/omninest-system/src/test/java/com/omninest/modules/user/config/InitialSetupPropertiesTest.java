package com.omninest.modules.user.config;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

/**
 * 首次安装配置测试。
 *
 * @author OmniNest
 */
class InitialSetupPropertiesTest {

    @Test
    void enablesWizardWithoutProvidingDefaultToken() {
        InitialSetupProperties properties = new InitialSetupProperties();

        assertThat(properties.isEnabled()).isTrue();
        assertThat(properties.getToken()).isNull();
        assertThat(properties.isPersistentStateEnabled()).isTrue();
    }
}
