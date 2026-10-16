package com.omninest.modules.user.dto;

import static org.assertj.core.api.Assertions.assertThat;

import jakarta.validation.ConstraintViolation;
import jakarta.validation.Validation;
import jakarta.validation.Validator;
import java.util.Set;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

class LoginRequestTest {

    private final Validator validator = Validation.buildDefaultValidatorFactory().getValidator();

    @Test
    @DisplayName("用户名超过 auth_users.username 列宽时校验失败")
    void validationFailsWhenUsernameExceedsColumnWidth() {
        LoginRequest request = new LoginRequest("u".repeat(81), "secret123");

        Set<ConstraintViolation<LoginRequest>> violations = validator.validate(request);

        assertThat(violations).isNotEmpty();
        assertThat(violations).allMatch(v -> v.getPropertyPath().toString().equals("username"));
    }

    @Test
    @DisplayName("用户名恰好 80 字符时校验通过")
    void validationPassesAtColumnWidthBoundary() {
        LoginRequest request = new LoginRequest("u".repeat(80), "secret123");

        assertThat(validator.validate(request)).isEmpty();
    }

    @Test
    @DisplayName("空用户名或空密码校验失败")
    void validationFailsWhenCredentialsBlank() {
        assertThat(validator.validate(new LoginRequest("", "secret123"))).isNotEmpty();
        assertThat(validator.validate(new LoginRequest("admin", ""))).isNotEmpty();
    }

    @Test
    @DisplayName("有效参数校验通过")
    void validationPassesWithValidInput() {
        assertThat(validator.validate(new LoginRequest("admin", "secret123"))).isEmpty();
    }
}
