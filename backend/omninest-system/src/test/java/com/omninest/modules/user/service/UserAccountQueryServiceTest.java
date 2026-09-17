package com.omninest.modules.user.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.security.Roles;
import com.omninest.modules.user.domain.AuthPermission;
import com.omninest.modules.user.domain.AuthRole;
import com.omninest.modules.user.domain.AuthUser;
import com.omninest.modules.user.repository.AuthUserRepository;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import org.junit.jupiter.api.Test;

/**
 * 用户账户查询服务测试。
 *
 * @author OmniNest
 */
class UserAccountQueryServiceTest {

    private static final UUID USER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID ROLE_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");

    private final AuthUserRepository authUserRepository = mock(AuthUserRepository.class);
    private final UserAccountQueryService service = new UserAccountQueryService(authUserRepository);

    /**
     * 验证实体角色和存储字段被映射为不可变摘要。
     */
    @Test
    void findByIdMapsAccountSummary() {
        AuthRole role = new AuthRole();
        role.setId(ROLE_ID);
        role.setCode(Roles.SUPER_ADMIN);
        AuthUser user = user(USER_ID, "root");
        user.setRoles(Set.of(role));
        user.setQuotaBytes(1024);
        user.setUsedBytes(512);
        when(authUserRepository.findWithRolesById(USER_ID)).thenReturn(Optional.of(user));

        var result = service.findById(USER_ID).orElseThrow();

        assertThat(result.username()).isEqualTo("root");
        assertThat(result.roleIds()).containsExactly(ROLE_ID);
        assertThat(result.superAdmin()).isTrue();
        assertThat(result.quotaBytes()).isEqualTo(1024);
        assertThat(result.usedBytes()).isEqualTo(512);
    }

    /**
     * 验证账户详情保留管理接口依赖的用户、角色、权限和配额字段。
     */
    @Test
    void findDetailsByIdMapsPublicAccountContract() {
        AuthPermission permission = new AuthPermission();
        permission.setCode("system:user:manage");
        permission.setEnabled(true);
        AuthRole role = new AuthRole();
        role.setCode(Roles.ADMIN);
        role.setEnabled(true);
        role.setPermissions(Set.of(permission));
        AuthUser user = user(USER_ID, "alice");
        user.setDisplayName("Alice");
        user.setEmail("alice@example.com");
        user.setStatus("ACTIVE");
        user.setRoles(Set.of(role));
        user.setQuotaBytes(2048);
        user.setUsedBytes(256);
        when(authUserRepository.findWithRolesAndPermissionsById(USER_ID)).thenReturn(Optional.of(user));

        var result = service.findDetailsById(USER_ID).orElseThrow();

        assertThat(result.id()).isEqualTo(USER_ID);
        assertThat(result.username()).isEqualTo("alice");
        assertThat(result.displayName()).isEqualTo("Alice");
        assertThat(result.email()).isEqualTo("alice@example.com");
        assertThat(result.status()).isEqualTo("ACTIVE");
        assertThat(result.role()).isEqualTo(Roles.ADMIN);
        assertThat(result.roles()).containsExactly(Roles.ADMIN);
        assertThat(result.permissions()).containsExactly("system:user:manage");
        assertThat(result.quotaBytes()).isEqualTo(2048);
        assertThat(result.usedBytes()).isEqualTo(256);
    }

    /**
     * 验证批量用户名查询不会向调用方暴露用户实体。
     */
    @Test
    void findUsernamesReturnsIdMap() {
        UUID secondId = UUID.fromString("10000000-0000-0000-0000-000000000002");
        when(authUserRepository.findAllById(List.of(USER_ID, secondId)))
                .thenReturn(List.of(user(USER_ID, "alice"), user(secondId, "bob")));

        var result = service.findUsernames(List.of(USER_ID, secondId));

        assertThat(result).containsEntry(USER_ID, "alice").containsEntry(secondId, "bob");
    }

    @Test
    void findIdsAfterUsesBoundedCursorQueries() {
        UUID cursor = UUID.fromString("10000000-0000-0000-0000-000000000000");
        when(authUserRepository.findFirstUserIds(500)).thenReturn(List.of(USER_ID));
        when(authUserRepository.findUserIdsAfter(cursor, 20)).thenReturn(List.of(USER_ID));

        assertThat(service.findIdsAfter(null, 900)).containsExactly(USER_ID);
        assertThat(service.findIdsAfter(cursor, 20)).containsExactly(USER_ID);
        verify(authUserRepository).findFirstUserIds(500);
        verify(authUserRepository).findUserIdsAfter(cursor, 20);
    }

    private AuthUser user(UUID id, String username) {
        AuthUser user = new AuthUser();
        user.setId(id);
        user.setUsername(username);
        return user;
    }
}
