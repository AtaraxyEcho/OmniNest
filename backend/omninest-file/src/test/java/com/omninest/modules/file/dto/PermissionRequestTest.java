package com.omninest.modules.file.dto;

import jakarta.validation.ConstraintViolation;
import jakarta.validation.Validation;
import jakarta.validation.Validator;
import java.util.Set;
import java.util.stream.Collectors;
import org.assertj.core.api.Assertions;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * 文件权限请求的必填校验测试。
 *
 * @author OmniNest
 */
class PermissionRequestTest {

    private final Validator validator = Validation.buildDefaultValidatorFactory().getValidator();

    @Test
    @DisplayName("权限位缺席时逐条报必填违规，不再按 false 静默执行")
    void validationFailsWhenAnyPermissionIsAbsent() {
        PermissionRequest request = new PermissionRequest(true, null, null);

        Set<ConstraintViolation<PermissionRequest>> violations = validator.validate(request);

        Assertions.assertThat(violations).hasSize(2);
        Assertions.assertThat(violations.stream()
                        .map(violation -> violation.getPropertyPath().toString())
                        .collect(Collectors.toSet()))
                .containsExactlyInAnyOrder("allowShare", "allowEdit");
    }

    @Test
    @DisplayName("三个权限位全部缺席时三条违规齐发")
    void validationFailsWhenAllPermissionsAreAbsent() {
        PermissionRequest request = new PermissionRequest(null, null, null);

        Assertions.assertThat(validator.validate(request)).hasSize(3);
    }

    @Test
    @DisplayName("显式拒绝与缺席可区分：全为 false 校验通过")
    void validationPassesWhenPermissionsAreExplicitlyFalse() {
        PermissionRequest request = new PermissionRequest(false, false, false);

        Assertions.assertThat(validator.validate(request)).isEmpty();
    }

    @Test
    @DisplayName("完整权限组合校验通过")
    void validationPassesWithCompletePermissionSet() {
        PermissionRequest request = new PermissionRequest(true, true, false);

        Assertions.assertThat(validator.validate(request)).isEmpty();
    }
}
