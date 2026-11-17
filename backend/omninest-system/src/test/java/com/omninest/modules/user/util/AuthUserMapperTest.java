package com.omninest.modules.user.util;

import static org.assertj.core.api.Assertions.assertThat;

import com.omninest.common.security.Roles;
import com.omninest.modules.user.domain.AuthPermission;
import com.omninest.modules.user.domain.AuthRole;
import com.omninest.modules.user.domain.AuthUser;
import com.omninest.modules.user.dto.AuthUserDto;
import java.util.Set;
import java.util.UUID;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

class AuthUserMapperTest {

    // ---- 辅助方法 ----

    private static AuthRole createRole(String code, boolean enabled, AuthPermission... permissions) {
        AuthRole role = new AuthRole();
        role.setId(UUID.randomUUID());
        role.setCode(code);
        role.setName(code);
        role.setEnabled(enabled);
        for (AuthPermission p : permissions) {
            role.getPermissions().add(p);
        }
        return role;
    }

    private static AuthPermission createPermission(String code, boolean enabled) {
        AuthPermission perm = new AuthPermission();
        perm.setId(UUID.randomUUID());
        perm.setCode(code);
        perm.setName(code);
        perm.setEnabled(enabled);
        return perm;
    }

    private static AuthUser createUser(AuthRole... roles) {
        AuthUser user = new AuthUser();
        user.setId(UUID.randomUUID());
        user.setUsername("testuser");
        user.setDisplayName("Test User");
        user.setEmail("test@example.com");
        user.setStatus("ACTIVE");
        user.setQuotaBytes(10L * 1024 * 1024 * 1024);
        user.setUsedBytes(500L);
        for (AuthRole role : roles) {
            user.getRoles().add(role);
        }
        return user;
    }

    // ---- roleCodes 测试 ----

    @Nested
    @DisplayName("roleCodes")
    class RoleCodesTests {

        @Test
        @DisplayName("返回已启用角色的代码集合")
        void returnsEnabledRoleCodes() {
            AuthRole admin = createRole(Roles.ADMIN, true);
            AuthRole member = createRole(Roles.MEMBER, true);
            AuthUser user = createUser(admin, member);

            Set<String> codes = AuthUserMapper.roleCodes(user);

            assertThat(codes).containsExactly(Roles.ADMIN, Roles.MEMBER);
        }

        @Test
        @DisplayName("排除已禁用的角色")
        void excludesDisabledRoles() {
            AuthRole admin = createRole(Roles.ADMIN, true);
            AuthRole member = createRole(Roles.MEMBER, false);
            AuthUser user = createUser(admin, member);

            Set<String> codes = AuthUserMapper.roleCodes(user);

            assertThat(codes).containsExactly(Roles.ADMIN);
        }

        @Test
        @DisplayName("无角色时返回空集合")
        void returnsEmptySetWhenNoRoles() {
            AuthUser user = createUser();

            Set<String> codes = AuthUserMapper.roleCodes(user);

            assertThat(codes).isEmpty();
        }

        @Test
        @DisplayName("结果按自然顺序排序")
        void sortedByNaturalOrder() {
            AuthRole guest = createRole(Roles.GUEST, true);
            AuthRole admin = createRole(Roles.ADMIN, true);
            AuthRole member = createRole(Roles.MEMBER, true);
            AuthUser user = createUser(guest, admin, member);

            Set<String> codes = AuthUserMapper.roleCodes(user);

            assertThat(codes).containsExactly(Roles.ADMIN, Roles.GUEST, Roles.MEMBER);
        }
    }

    // ---- permissionCodes 测试 ----

    @Nested
    @DisplayName("permissionCodes")
    class PermissionCodesTests {

        @Test
        @DisplayName("返回已启用角色下已启用权限的代码集合")
        void returnsEnabledPermissionCodes() {
            AuthPermission perm1 = createPermission("USER_READ", true);
            AuthPermission perm2 = createPermission("USER_WRITE", true);
            AuthRole role = createRole(Roles.ADMIN, true, perm1, perm2);
            AuthUser user = createUser(role);

            Set<String> codes = AuthUserMapper.permissionCodes(user);

            assertThat(codes).containsExactly("USER_READ", "USER_WRITE");
        }

        @Test
        @DisplayName("排除已禁用角色的权限")
        void excludesPermissionsFromDisabledRoles() {
            AuthPermission perm = createPermission("USER_READ", true);
            AuthRole disabledRole = createRole(Roles.ADMIN, false, perm);
            AuthUser user = createUser(disabledRole);

            Set<String> codes = AuthUserMapper.permissionCodes(user);

            assertThat(codes).isEmpty();
        }

        @Test
        @DisplayName("排除已禁用的权限")
        void excludesDisabledPermissions() {
            AuthPermission enabled = createPermission("USER_READ", true);
            AuthPermission disabled = createPermission("USER_WRITE", false);
            AuthRole role = createRole(Roles.ADMIN, true, enabled, disabled);
            AuthUser user = createUser(role);

            Set<String> codes = AuthUserMapper.permissionCodes(user);

            assertThat(codes).containsExactly("USER_READ");
        }

        @Test
        @DisplayName("多角色权限合并并去重")
        void mergesPermissionsFromMultipleRoles() {
            AuthPermission shared = createPermission("USER_READ", true);
            AuthPermission adminOnly = createPermission("USER_DELETE", true);
            AuthRole role1 = createRole(Roles.MEMBER, true, shared);
            AuthRole role2 = createRole(Roles.ADMIN, true, shared, adminOnly);
            AuthUser user = createUser(role1, role2);

            Set<String> codes = AuthUserMapper.permissionCodes(user);

            assertThat(codes).containsExactly("USER_DELETE", "USER_READ");
        }

        @Test
        @DisplayName("无角色时返回空集合")
        void returnsEmptySetWhenNoRoles() {
            AuthUser user = createUser();

            Set<String> codes = AuthUserMapper.permissionCodes(user);

            assertThat(codes).isEmpty();
        }
    }

    // ---- primaryRole 测试 ----

    @Nested
    @DisplayName("primaryRole")
    class PrimaryRoleTests {

        @Test
        @DisplayName("SUPER_ADMIN 优先级最高")
        void superAdminHasHighestPriority() {
            AuthRole sa = createRole(Roles.SUPER_ADMIN, true);
            AuthRole admin = createRole(Roles.ADMIN, true);
            AuthRole member = createRole(Roles.MEMBER, true);
            AuthUser user = createUser(sa, admin, member);

            assertThat(AuthUserMapper.primaryRole(user)).isEqualTo(Roles.SUPER_ADMIN);
        }

        @Test
        @DisplayName("ADMIN 优先于 MEMBER")
        void adminHasPriorityOverMember() {
            AuthRole admin = createRole(Roles.ADMIN, true);
            AuthRole member = createRole(Roles.MEMBER, true);
            AuthUser user = createUser(admin, member);

            assertThat(AuthUserMapper.primaryRole(user)).isEqualTo(Roles.ADMIN);
        }

        @Test
        @DisplayName("MEMBER 优先于 GUEST")
        void memberHasPriorityOverGuest() {
            AuthRole member = createRole(Roles.MEMBER, true);
            AuthRole guest = createRole(Roles.GUEST, true);
            AuthUser user = createUser(member, guest);

            assertThat(AuthUserMapper.primaryRole(user)).isEqualTo(Roles.MEMBER);
        }

        @Test
        @DisplayName("仅有 GUEST 时返回 GUEST")
        void returnsGuestWhenOnlyGuest() {
            AuthRole guest = createRole(Roles.GUEST, true);
            AuthUser user = createUser(guest);

            assertThat(AuthUserMapper.primaryRole(user)).isEqualTo(Roles.GUEST);
        }

        @Test
        @DisplayName("无角色时返回 GUEST")
        void returnsGuestWhenNoRoles() {
            AuthUser user = createUser();

            assertThat(AuthUserMapper.primaryRole(user)).isEqualTo(Roles.GUEST);
        }

        @Test
        @DisplayName("已禁用角色不影响优先级计算")
        void disabledRolesIgnored() {
            AuthRole disabledAdmin = createRole(Roles.ADMIN, false);
            AuthRole member = createRole(Roles.MEMBER, true);
            AuthUser user = createUser(disabledAdmin, member);

            assertThat(AuthUserMapper.primaryRole(user)).isEqualTo(Roles.MEMBER);
        }

        @Test
        @DisplayName("从 Set<String> 计算主要角色")
        void primaryRoleFromSet() {
            Set<String> roles = Set.of(Roles.MEMBER, Roles.ADMIN);

            assertThat(AuthUserMapper.primaryRole(roles)).isEqualTo(Roles.ADMIN);
        }

        @Test
        @DisplayName("空 Set 返回 GUEST")
        void primaryRoleFromEmptySet() {
            assertThat(AuthUserMapper.primaryRole(Set.of())).isEqualTo(Roles.GUEST);
        }
    }

    // ---- toDto 测试 ----

    @Nested
    @DisplayName("toDto")
    class ToDtoTests {

        @Test
        @DisplayName("正确映射所有字段")
        void mapsAllFieldsCorrectly() {
            AuthPermission perm = createPermission("USER_READ", true);
            AuthRole role = createRole(Roles.ADMIN, true, perm);
            AuthUser user = createUser(role);

            AuthUserDto dto = AuthUserMapper.toDto(user, "https://example.com/avatar.jpg");

            assertThat(dto.id()).isEqualTo(user.getId());
            assertThat(dto.username()).isEqualTo("testuser");
            assertThat(dto.displayName()).isEqualTo("Test User");
            assertThat(dto.avatarUrl()).isEqualTo("https://example.com/avatar.jpg");
            assertThat(dto.email()).isEqualTo("test@example.com");
            assertThat(dto.status()).isEqualTo("ACTIVE");
            assertThat(dto.role()).isEqualTo(Roles.ADMIN);
            assertThat(dto.roles()).containsExactly(Roles.ADMIN);
            assertThat(dto.permissions()).containsExactly("USER_READ");
            assertThat(dto.quotaBytes()).isEqualTo(10L * 1024 * 1024 * 1024);
            assertThat(dto.usedBytes()).isEqualTo(500L);
        }

        @Test
        @DisplayName("avatarUrl 为 null 时正确传递")
        void nullAvatarUrlPassedThrough() {
            AuthRole role = createRole(Roles.MEMBER, true);
            AuthUser user = createUser(role);

            AuthUserDto dto = AuthUserMapper.toDto(user, null);

            assertThat(dto.avatarUrl()).isNull();
        }
    }
}
