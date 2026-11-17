package com.omninest.modules.user.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.omninest.common.config.ConfigValueProvider;
import com.omninest.modules.user.repository.AuthUserRepository;
import com.omninest.common.config.RuntimeConfigCache;
import com.omninest.common.security.Roles;
import com.omninest.modules.user.domain.AuthRole;
import com.omninest.modules.user.domain.AuthUser;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * 两步验证强制策略测试。
 *
 * @author OmniNest
 */
class TwoFactorPolicyServiceTest {

    private final ConfigValueProvider configValueProvider = mock(ConfigValueProvider.class);
    private final RuntimeConfigCache runtimeConfigCache = mock(RuntimeConfigCache.class);

    private TwoFactorPolicyService service;

    @BeforeEach
    void setUp() {
        AuthUserRepository authUserRepository = mock(AuthUserRepository.class);
        service = new TwoFactorPolicyService(configValueProvider, runtimeConfigCache, authUserRepository);
        when(runtimeConfigCache.get(anyString())).thenReturn(Optional.empty());
        when(configValueProvider.findByKey(anyString())).thenReturn(Optional.empty());
    }

    @Test
    @DisplayName("配置缺失时默认超管与管理员强制")
    void defaultsToSuperAdminAndAdmin() {
        assertThat(service.requiredRoles())
                .containsExactlyInAnyOrder(Roles.SUPER_ADMIN, Roles.ADMIN);
    }

    @Test
    @DisplayName("逗号列表支持空白与大小写差异")
    void parsesCommaSeparatedRolesTolerantly() {
        when(configValueProvider.findByKey(TwoFactorPolicyService.REQUIRED_ROLES_KEY))
                .thenReturn(Optional.of(" super_admin , admin , "));

        assertThat(service.requiredRoles())
                .containsExactlyInAnyOrder("SUPER_ADMIN", "ADMIN");
    }

    @Test
    @DisplayName("留空配置表示全员自愿")
    void emptyConfigMeansVoluntary() {
        when(configValueProvider.findByKey(TwoFactorPolicyService.REQUIRED_ROLES_KEY))
                .thenReturn(Optional.of("  "));

        assertThat(service.requiredRoles()).isEmpty();
        assertThat(service.isRequired(userWithRole(Roles.ADMIN))).isFalse();
    }

    @Test
    @DisplayName("用户角色命中强制清单时返回 true")
    void matchesUserRoleCaseInsensitively() {
        AuthUser user = userWithRole("Admin");

        assertThat(service.isRequired(user)).isTrue();
        assertThat(service.isRequired(userWithRole(Roles.MEMBER))).isFalse();
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
