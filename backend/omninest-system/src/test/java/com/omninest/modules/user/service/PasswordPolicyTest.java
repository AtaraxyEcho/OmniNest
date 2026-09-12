package com.omninest.modules.user.service;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.omninest.common.error.BusinessException;
import org.junit.jupiter.api.Test;

/**
 * 统一密码策略测试。
 *
 * @author OmniNest
 */
class PasswordPolicyTest {

    private final PasswordPolicy passwordPolicy = new PasswordPolicy();

    @Test
    void acceptsStrongPassword() {
        assertThatCode(() -> passwordPolicy.validate("root", "ChangeMe123!"))
                .doesNotThrowAnyException();
    }

    @Test
    void rejectsShortPassword() {
        assertThatThrownBy(() -> passwordPolicy.validate("root", "short"))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("8 到 24");
    }

    @Test
    void rejectsOverlongPassword() {
        assertThatThrownBy(() -> passwordPolicy.validate("root", "a".repeat(25)))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("8 到 24");
    }

    @Test
    void rejectsCommonPasswordAndUsername() {
        assertThatThrownBy(() -> passwordPolicy.validate("root", "password123"))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("弱口令");
        assertThatThrownBy(() -> passwordPolicy.validate("RootUser", "rootuser"))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("用户名相同");
    }
}
