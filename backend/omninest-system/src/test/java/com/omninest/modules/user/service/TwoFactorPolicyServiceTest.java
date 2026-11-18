package com.omninest.modules.user.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;

import com.omninest.modules.user.repository.AuthUserRepository;
import com.omninest.common.security.Roles;
import com.omninest.modules.user.domain.AuthRole;
import com.omninest.modules.user.domain.AuthUser;
import java.util.UUID;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * 两步验证强制策略测试。
 *
 * @author OmniNest
 */
class TwoFactorPolicyServiceTest {

    private final TwoFactorPolicyService service =
            new TwoFactorPolicyService(mock(AuthUserRepository.class));

    @Test
    @DisplayName("仅超管必须开启两步验证")
    void onlySuperAdminMustEnroll() {
        assertThat(service.isRequired(userWithRole(Roles.SUPER_ADMIN))).isTrue();
        assertThat(service.isRequired(userWithRole(Roles.ADMIN))).isFalse();
        assertThat(service.isRequired(userWithRole(Roles.MEMBER))).isFalse();
    }

    @Test
    @DisplayName("超级管理员角色编码大小写不敏感")
    void superAdminRoleMatchesCaseInsensitively() {
        assertThat(service.isRequired(userWithRole("super_admin"))).isTrue();
        assertThat(service.isRequired(new AuthUser())).isFalse();
    }

    private AuthUser userWithRole(String roleCode) {
        AuthRole role = new AuthRole();
        role.setId(UUID.randomUUID());
        role.setCode(roleCode);
        AuthUser user = new AuthUser();
        user.setId(UUID.randomUUID());
        user.getRoles().add(role);
        return user;
    }
}
