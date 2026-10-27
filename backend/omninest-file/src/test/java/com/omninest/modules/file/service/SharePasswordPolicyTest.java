package com.omninest.modules.file.service;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.omninest.common.error.BusinessException;
import org.junit.jupiter.api.Test;

/**
 * 分享密码编码边界测试。
 *
 * @author OmniNest
 */
class SharePasswordPolicyTest {

    @Test
    void acceptsPasswordAtByteLimit() {
        // 72 个 ASCII 字符正好是 BCrypt 允许的上限。
        assertThatCode(() -> SharePasswordPolicy.requireEncodable("a".repeat(72)))
                .doesNotThrowAnyException();
    }

    @Test
    void rejectsMultiBytePasswordBeyondByteLimit() {
        // 24 个汉字刚好 72 字节；25 个越界，必须转成参数错误而不是让 BCrypt 抛 IllegalArgumentException。
        assertThatCode(() -> SharePasswordPolicy.requireEncodable("中".repeat(24)))
                .doesNotThrowAnyException();
        assertThatThrownBy(() -> SharePasswordPolicy.requireEncodable("中".repeat(25)))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("72");
    }

    @Test
    void ignoresAbsentPassword() {
        assertThatCode(() -> SharePasswordPolicy.requireEncodable(null))
                .doesNotThrowAnyException();
    }
}
