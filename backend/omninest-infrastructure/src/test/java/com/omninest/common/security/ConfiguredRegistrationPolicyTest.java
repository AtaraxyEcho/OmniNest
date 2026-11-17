package com.omninest.common.security;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.omninest.common.config.SecurityProperties;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import org.junit.jupiter.api.Test;

class ConfiguredRegistrationPolicyTest {

    @Test
    void rejectsRegistrationByDefault() {
        SecurityProperties properties = new SecurityProperties();
        ConfiguredRegistrationPolicy policy = new ConfiguredRegistrationPolicy(properties);

        assertThatThrownBy(policy::requireRegistrationEnabled)
                .isInstanceOfSatisfying(BusinessException.class, exception ->
                        assertThat(exception.errorCode()).isEqualTo(ErrorCode.REGISTRATION_DISABLED));
    }

    @Test
    void allowsRegistrationWhenExplicitlyEnabled() {
        SecurityProperties properties = new SecurityProperties();
        properties.setRegistrationEnabled(true);
        ConfiguredRegistrationPolicy policy = new ConfiguredRegistrationPolicy(properties);

        assertThatCode(policy::requireRegistrationEnabled).doesNotThrowAnyException();
    }
}
