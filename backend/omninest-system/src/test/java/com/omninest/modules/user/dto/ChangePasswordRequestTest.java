package com.omninest.modules.user.dto;

import static org.assertj.core.api.Assertions.assertThat;

import jakarta.validation.ConstraintViolation;
import jakarta.validation.Validation;
import jakarta.validation.Validator;
import java.util.Set;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

class ChangePasswordRequestTest {

    private final Validator validator = Validation.buildDefaultValidatorFactory().getValidator();

    @Test
    @DisplayName("oldPassword 为空时校验失败")
    void validationFailsWhenOldPasswordBlank() {
        var request = new ChangePasswordRequest("", "newpass123");

        Set<ConstraintViolation<ChangePasswordRequest>> violations = validator.validate(request);

        assertThat(violations).isNotEmpty();
        assertThat(violations).anyMatch(v -> v.getPropertyPath().toString().equals("oldPassword"));
    }

    @Test
    @DisplayName("newPassword 为空时校验失败")
    void validationFailsWhenNewPasswordBlank() {
        var request = new ChangePasswordRequest("oldpass", "");

        Set<ConstraintViolation<ChangePasswordRequest>> violations = validator.validate(request);

        assertThat(violations).isNotEmpty();
        assertThat(violations).anyMatch(v -> v.getPropertyPath().toString().equals("newPassword"));
    }

    @Test
    @DisplayName("有效参数校验通过")
    void validationPassesWithValidInput() {
        var request = new ChangePasswordRequest("oldpass", "newpass123");

        Set<ConstraintViolation<ChangePasswordRequest>> violations = validator.validate(request);

        assertThat(violations).isEmpty();
    }
}
