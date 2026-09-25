package com.omninest.common.config;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.core.env.StandardEnvironment;

class JwtSecretValidationTest {

    @Test
    @DisplayName("dev 启动成功：JWT secret 使用兼容默认值")
    void startupSucceedsWhenJwtSecretIsDefaultInDev() {
        SecurityProperties props = new SecurityProperties();
        assertThatCode(() -> new JwtSecretValidator(props, new StandardEnvironment()).validate(false))
                .doesNotThrowAnyException();
    }

    @Test
    @DisplayName("prod 启动失败：JWT secret 使用兼容默认值")
    void startupFailsWhenJwtSecretIsDefaultInProd() {
        SecurityProperties props = new SecurityProperties();
        assertThatThrownBy(() -> new JwtSecretValidator(props, new StandardEnvironment()).validate(true))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("OMNINEST_SECURITY_JWT_SECRET");
    }

    @Test
    @DisplayName("应用启动失败：JWT secret 为空或长度不足")
    void startupFailsWhenJwtSecretIsBlankOrTooShort() {
        SecurityProperties props = new SecurityProperties();
        props.setJwtSecret("short-secret");

        assertThatThrownBy(() -> new JwtSecretValidator(props, new StandardEnvironment()).validate(false))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("32");
    }

    @Test
    @DisplayName("应用启动成功：JWT secret 已修改")
    void startupSucceedsWhenJwtSecretChanged() {
        SecurityProperties props = new SecurityProperties();
        props.setJwtSecret("my-custom-secret-key-at-least-32-bytes-long!");
        new JwtSecretValidator(props, new StandardEnvironment()).validate(true);
    }
}
