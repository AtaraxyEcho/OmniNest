package com.omninest.modules.user.service;

import com.omninest.common.security.Permissions;
import com.omninest.common.security.Roles;
import com.omninest.modules.user.config.InitialSetupProperties;
import com.omninest.modules.user.domain.AuthPermission;
import com.omninest.modules.user.domain.AuthRole;
import com.omninest.modules.user.domain.SystemInstance;
import com.omninest.modules.user.repository.AuthPermissionRepository;
import com.omninest.modules.user.repository.AuthRoleRepository;
import com.omninest.modules.user.repository.SystemInstanceRepository;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import org.assertj.core.api.Assertions;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;

/**
 * 首次安装核心目录校验测试。
 *
 * @author OmniNest
 */
class CoreCatalogValidatorTest {
    private final AuthRoleRepository authRoleRepository = Mockito.mock(AuthRoleRepository.class);
    private final AuthPermissionRepository authPermissionRepository = Mockito.mock(AuthPermissionRepository.class);
    private final SystemInstanceRepository systemInstanceRepository = Mockito.mock(SystemInstanceRepository.class);
    private final InitialSetupProperties properties = new InitialSetupProperties();
    private final CoreCatalogValidator validator = new CoreCatalogValidator(
            authRoleRepository,
            authPermissionRepository,
            systemInstanceRepository,
            properties
    );

    private Set<AuthPermission> permissions;
    private List<AuthRole> roles;

    @BeforeEach
    void setUp() {
        permissions = permissionCatalog();
        roles = roleCatalog(permissions);
        properties.setPersistentStateEnabled(true);
        Mockito.when(authRoleRepository.findAllWithPermissions(org.springframework.data.domain.Sort.unsorted())).thenReturn(roles);
        Mockito.when(authPermissionRepository.findByCodeIn(Permissions.SUPER_ADMIN_PERMISSIONS))
                .thenReturn(permissions);
        Mockito.when(systemInstanceRepository.existsById(SystemInstance.SINGLETON_ID)).thenReturn(true);
    }

    @Test
    void acceptsCompleteCoreCatalog() {
        Assertions.assertThatCode(() -> validator.run(null)).doesNotThrowAnyException();
    }

    @Test
    void doesNotRequireInstanceRowWhenPersistentStateIsDisabled() {
        properties.setPersistentStateEnabled(false);

        Assertions.assertThatCode(() -> validator.run(null)).doesNotThrowAnyException();
        Mockito.verify(systemInstanceRepository, Mockito.never()).existsById(SystemInstance.SINGLETON_ID);
    }

    @Test
    void rejectsMissingBuiltInPermission() {
        AuthPermission missingPermission = permissions.iterator().next();
        permissions.remove(missingPermission);

        Assertions.assertThatThrownBy(() -> validator.run(null))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("内置权限目录缺失");
    }

    private Set<AuthPermission> permissionCatalog() {
        Set<AuthPermission> result = new HashSet<>();
        for (String code : Permissions.SUPER_ADMIN_PERMISSIONS) {
            AuthPermission permission = new AuthPermission();
            permission.setId(UUID.randomUUID());
            permission.setCode(code);
            permission.setName(code);
            permission.setModule("test");
            permission.setEnabled(true);
            result.add(permission);
        }
        return result;
    }

    private List<AuthRole> roleCatalog(Set<AuthPermission> availablePermissions) {
        List<AuthRole> result = new ArrayList<>();
        for (String code : List.of(Roles.SUPER_ADMIN, Roles.ADMIN, Roles.MEMBER, Roles.GUEST)) {
            AuthRole role = new AuthRole();
            role.setId(UUID.randomUUID());
            role.setCode(code);
            role.setName(code);
            role.setEnabled(true);
            if (Roles.SUPER_ADMIN.equals(code)) {
                role.setPermissions(new HashSet<>(availablePermissions));
            }
            result.add(role);
        }
        return result;
    }
}
