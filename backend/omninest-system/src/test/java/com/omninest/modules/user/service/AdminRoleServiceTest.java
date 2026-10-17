package com.omninest.modules.user.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.security.Permissions;
import com.omninest.common.security.Roles;
import com.omninest.modules.user.domain.AuthPermission;
import com.omninest.modules.user.domain.AuthRole;
import com.omninest.modules.user.domain.AuthUser;
import com.omninest.modules.user.dto.AdminOperationsDto;
import com.omninest.modules.user.repository.AuthPermissionRepository;
import com.omninest.modules.user.repository.AuthRoleRepository;
import com.omninest.modules.user.repository.AuthUserRepository;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.data.domain.Sort;

/**
 * 角色与权限绑定维护测试：覆盖内置角色边界、授予子集约束与模板克隆边界。
 *
 * <p>操作者边界使用真实的 {@link AdminActorGuard}（挂在打桩仓储上），
 * 使子集判定与其调用方一起被验证，而不是被替身吞掉。</p>
 *
 * @author OmniNest
 */
class AdminRoleServiceTest {
    private final AuthRoleRepository authRoleRepository = mock(AuthRoleRepository.class);
    private final AuthUserRepository authUserRepository = mock(AuthUserRepository.class);
    private final AuthPermissionRepository authPermissionRepository = mock(AuthPermissionRepository.class);
    private final AdminAuditLogService auditLogService = mock(AdminAuditLogService.class);
    private final UserSessionRevocationService userSessionRevocationService =
            mock(UserSessionRevocationService.class);
    private final AdminActorGuard adminActorGuard = new AdminActorGuard(authUserRepository);
    private final AdminRoleService service = new AdminRoleService(
            authRoleRepository,
            authUserRepository,
            authPermissionRepository,
            auditLogService,
            userSessionRevocationService,
            adminActorGuard
    );
    private final UUID actorUserId = UUID.fromString("99999999-9999-9999-9999-999999999999");

    /**
     * 具备全部待授予权限的操作者：超级管理员不受子集与内置角色约束，用于覆盖通用写入路径。
     */
    private void givenFreshAdminActor() {
        AuthUser actor = new AuthUser();
        actor.setId(actorUserId);
        actor.setStatus("ACTIVE");
        actor.getRoles().add(role(Roles.SUPER_ADMIN,
                permission(Permissions.SYSTEM_USER_READ, "system"),
                permission(Permissions.SYSTEM_USER_MANAGE, "system")));
        when(authUserRepository.findWithRolesAndPermissionsById(actorUserId)).thenReturn(Optional.of(actor));
    }

    /**
     * 只持有 system:user:read 的普通管理员：用于覆盖权限子集与内置角色维护边界。
     */
    private AuthUser givenRestrictedAdminActor() {
        AuthUser actor = new AuthUser();
        actor.setId(actorUserId);
        actor.setStatus("ACTIVE");
        actor.getRoles().add(role(Roles.ADMIN, permission(Permissions.SYSTEM_USER_READ, "system")));
        when(authUserRepository.findWithRolesAndPermissionsById(actorUserId)).thenReturn(Optional.of(actor));
        return actor;
    }

    @Test
    void rolesReturnsRolePermissionDetails() {
        AuthRole admin = role(Roles.ADMIN, permission(Permissions.SYSTEM_USER_READ, "system"));
        AuthPermission manageUsers = permission(Permissions.SYSTEM_USER_MANAGE, "system");
        when(authRoleRepository.findAllWithPermissions(Sort.by(Sort.Direction.ASC, "code"))).thenReturn(List.of(admin));
        when(authPermissionRepository.findAll(Sort.by(Sort.Direction.ASC, "module", "code")))
                .thenReturn(List.of(manageUsers));

        AdminOperationsDto.RoleManagementView view = service.roles();

        assertThat(view.roles()).hasSize(1);
        assertThat(view.roles().get(0).code()).isEqualTo(Roles.ADMIN);
        assertThat(view.roles().get(0).permissions()).containsExactly(Permissions.SYSTEM_USER_READ);
        assertThat(view.permissions()).extracting("code").containsExactly(Permissions.SYSTEM_USER_MANAGE);
    }

    @Test
    void updateRolePermissionsReplacesMutableRolePermissions() {
        givenFreshAdminActor();
        AuthRole admin = role(Roles.ADMIN, permission(Permissions.SYSTEM_USER_READ, "system"));
        AuthPermission manageUsers = permission(Permissions.SYSTEM_USER_MANAGE, "system");
        AuthUser affectedUser = new AuthUser();
        affectedUser.setId(UUID.fromString("10000000-0000-0000-0000-000000000001"));
        when(authRoleRepository.findByCode(Roles.ADMIN)).thenReturn(Optional.of(admin));
        when(authPermissionRepository.findByCodeIn(Set.of(Permissions.SYSTEM_USER_MANAGE)))
                .thenReturn(Set.of(manageUsers));
        when(authUserRepository.findAllByRoles_Code(Roles.ADMIN)).thenReturn(List.of(affectedUser));

        AdminOperationsDto.RoleDetail updated = service.updateRolePermissions(
                actorUserId,
                Roles.ADMIN,
                new AdminOperationsDto.UpdateRolePermissionsRequest(Set.of(Permissions.SYSTEM_USER_MANAGE))
        );

        assertThat(updated.permissions()).containsExactly(Permissions.SYSTEM_USER_MANAGE);
        assertThat(admin.getPermissions()).containsExactly(manageUsers);
        verify(userSessionRevocationService).revokeAll(List.of(affectedUser.getId()), "管理员更新角色权限");
        ArgumentCaptor<Map<String, Object>> payloadCaptor = ArgumentCaptor.captor();
        verify(auditLogService).recordWithPayload(
                eq(actorUserId), eq("ADMIN_ROLE_PERMISSIONS_UPDATE"), eq("auth_roles"), eq(admin.getId()),
                payloadCaptor.capture());
        assertThat(payloadCaptor.getValue())
                .containsEntry("oldValue", List.of(Permissions.SYSTEM_USER_READ))
                .containsEntry("newValue", List.of(Permissions.SYSTEM_USER_MANAGE))
                .containsEntry("changeBy", actorUserId.toString());
    }

    @Test
    void updateRolePermissionsRejectsSuperAdmin() {
        givenFreshAdminActor();
        assertThatThrownBy(() -> service.updateRolePermissions(
                actorUserId,
                Roles.SUPER_ADMIN,
                new AdminOperationsDto.UpdateRolePermissionsRequest(Set.of(Permissions.SYSTEM_USER_READ))
        ))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.FORBIDDEN);
    }

    @Test
    void updateRolePermissionsRejectsActorWithoutAdminRole() {
        AuthUser actor = new AuthUser();
        actor.setId(actorUserId);
        actor.setStatus("ACTIVE");
        actor.getRoles().add(role(Roles.MEMBER, permission(Permissions.SYSTEM_USER_READ, "system")));
        when(authUserRepository.findWithRolesAndPermissionsById(actorUserId)).thenReturn(Optional.of(actor));

        assertThatThrownBy(() -> service.updateRolePermissions(
                actorUserId,
                Roles.ADMIN,
                new AdminOperationsDto.UpdateRolePermissionsRequest(Set.of(Permissions.SYSTEM_USER_MANAGE))
        ))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.FORBIDDEN);
    }

    @Test
    @DisplayName("普通管理员不得授予自身不具备的权限")
    void updateRolePermissionsRejectsGrantBeyondActorPermissions() {
        givenRestrictedAdminActor();
        AuthRole custom = role("ROLE_MEDIA_CURATOR");
        custom.setBuiltIn(false);
        when(authRoleRepository.findByCode("ROLE_MEDIA_CURATOR")).thenReturn(Optional.of(custom));
        when(authPermissionRepository.findByCodeIn(Set.of(Permissions.SYSTEM_USER_MANAGE)))
                .thenReturn(Set.of(permission(Permissions.SYSTEM_USER_MANAGE, "system")));

        assertThatThrownBy(() -> service.updateRolePermissions(
                actorUserId,
                "ROLE_MEDIA_CURATOR",
                new AdminOperationsDto.UpdateRolePermissionsRequest(Set.of(Permissions.SYSTEM_USER_MANAGE))
        ))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.FORBIDDEN);
        verify(authRoleRepository, never()).save(any(AuthRole.class));
    }

    @Test
    @DisplayName("普通管理员不得维护内置角色权限矩阵")
    void updateRolePermissionsRejectsBuiltinRoleForNonSuperAdmin() {
        givenRestrictedAdminActor();
        AuthRole member = role(Roles.MEMBER, permission(Permissions.SYSTEM_USER_READ, "system"));
        when(authRoleRepository.findByCode(Roles.MEMBER)).thenReturn(Optional.of(member));

        assertThatThrownBy(() -> service.updateRolePermissions(
                actorUserId,
                Roles.MEMBER,
                new AdminOperationsDto.UpdateRolePermissionsRequest(Set.of(Permissions.SYSTEM_USER_READ))
        ))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.FORBIDDEN);
        verify(authRoleRepository, never()).save(any(AuthRole.class));
    }

    @Test
    @DisplayName("普通管理员可在自身权限范围内调整自定义角色")
    void updateRolePermissionsAcceptsPermissionWithinActorScope() {
        givenRestrictedAdminActor();
        AuthRole custom = role("ROLE_MEDIA_CURATOR", permission(Permissions.SYSTEM_USER_READ, "system"));
        custom.setBuiltIn(false);
        when(authRoleRepository.findByCode("ROLE_MEDIA_CURATOR")).thenReturn(Optional.of(custom));
        when(authPermissionRepository.findByCodeIn(Set.of(Permissions.SYSTEM_USER_READ)))
                .thenReturn(Set.of(permission(Permissions.SYSTEM_USER_READ, "system")));
        when(authUserRepository.findAllByRoles_Code("ROLE_MEDIA_CURATOR")).thenReturn(List.of());

        AdminOperationsDto.RoleDetail updated = service.updateRolePermissions(
                actorUserId,
                "ROLE_MEDIA_CURATOR",
                new AdminOperationsDto.UpdateRolePermissionsRequest(Set.of(Permissions.SYSTEM_USER_READ))
        );

        assertThat(updated.permissions()).containsExactly(Permissions.SYSTEM_USER_READ);
    }

    @Test
    @DisplayName("创建角色按模板克隆时同样受操作者权限范围约束")
    void createRoleRejectsTemplateBeyondActorPermissions() {
        givenRestrictedAdminActor();
        AuthRole template = role(Roles.MEMBER,
                permission(Permissions.SYSTEM_USER_READ, "system"),
                permission(Permissions.SYSTEM_USER_MANAGE, "system"));
        when(authRoleRepository.existsByCode("ROLE_MEDIA_CURATOR")).thenReturn(false);
        when(authRoleRepository.findWithPermissionsByCode(Roles.MEMBER)).thenReturn(Optional.of(template));

        assertThatThrownBy(() -> service.createRole(
                actorUserId,
                new AdminOperationsDto.CreateRoleRequest(
                        "ROLE_MEDIA_CURATOR", "媒体策展人", "自定义角色", "member")
        ))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.FORBIDDEN);
    }

    @Test
    void createRoleClonesTemplatePermissionsAndWritesAudit() {
        givenFreshAdminActor();
        AuthPermission userRead = permission(Permissions.SYSTEM_USER_READ, "system");
        AuthPermission userManage = permission(Permissions.SYSTEM_USER_MANAGE, "system");
        AuthRole template = role(Roles.MEMBER, userRead, userManage);
        when(authRoleRepository.existsByCode("ROLE_MEDIA_CURATOR")).thenReturn(false);
        when(authRoleRepository.findWithPermissionsByCode(Roles.MEMBER)).thenReturn(Optional.of(template));

        AdminOperationsDto.RoleDetail created = service.createRole(
                actorUserId,
                new AdminOperationsDto.CreateRoleRequest(
                        " role_media_curator ", "媒体策展人", "自定义角色", "member")
        );

        assertThat(created.code()).isEqualTo("ROLE_MEDIA_CURATOR");
        assertThat(created.name()).isEqualTo("媒体策展人");
        assertThat(created.builtIn()).isFalse();
        assertThat(created.enabled()).isTrue();
        assertThat(created.permissions())
                .containsExactly(Permissions.SYSTEM_USER_MANAGE, Permissions.SYSTEM_USER_READ);
        ArgumentCaptor<Map<String, Object>> payloadCaptor = ArgumentCaptor.captor();
        verify(auditLogService).recordWithPayload(
                eq(actorUserId), eq("ADMIN_ROLE_CREATE"), eq("auth_roles"), isNull(),
                payloadCaptor.capture());
        assertThat(payloadCaptor.getValue())
                .containsEntry("code", "ROLE_MEDIA_CURATOR")
                .containsEntry("baseTemplate", "MEMBER")
                .containsEntry("permissionCount", 2);
    }

    @Test
    void createRoleSupportsNoneTemplate() {
        givenFreshAdminActor();
        when(authRoleRepository.existsByCode("ROLE_EMPTY")).thenReturn(false);

        AdminOperationsDto.RoleDetail created = service.createRole(
                actorUserId,
                new AdminOperationsDto.CreateRoleRequest("ROLE_EMPTY", "空角色", null, null)
        );

        assertThat(created.permissions()).isEmpty();
        ArgumentCaptor<Map<String, Object>> payloadCaptor = ArgumentCaptor.captor();
        verify(auditLogService).recordWithPayload(
                eq(actorUserId), eq("ADMIN_ROLE_CREATE"), eq("auth_roles"), isNull(),
                payloadCaptor.capture());
        assertThat(payloadCaptor.getValue())
                .containsEntry("baseTemplate", "NONE")
                .containsEntry("permissionCount", 0);
    }

    @Test
    void createRoleRejectsInvalidCodeFormat() {
        givenFreshAdminActor();

        assertThatThrownBy(() -> service.createRole(
                actorUserId,
                new AdminOperationsDto.CreateRoleRequest("ADMIN", "管理员", null, "none")))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("ROLE_")
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.PARAM_ERROR);
        assertThatThrownBy(() -> service.createRole(
                actorUserId,
                new AdminOperationsDto.CreateRoleRequest("ROLE_MEDIA-CURATOR", "非法字符", null, "none")))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.PARAM_ERROR);
        assertThatThrownBy(() -> service.createRole(
                actorUserId,
                new AdminOperationsDto.CreateRoleRequest("ROLE_" + "X".repeat(64), "超长编码", null, "none")))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.PARAM_ERROR);
    }

    @Test
    void createRoleRejectsDuplicateCode() {
        givenFreshAdminActor();
        when(authRoleRepository.existsByCode("ROLE_MEDIA_CURATOR")).thenReturn(true);

        assertThatThrownBy(() -> service.createRole(
                actorUserId,
                new AdminOperationsDto.CreateRoleRequest("ROLE_MEDIA_CURATOR", "媒体策展人", null, "none")))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.CONFLICT);
    }

    @Test
    void createRoleRejectsUnknownBaseTemplate() {
        givenFreshAdminActor();

        assertThatThrownBy(() -> service.createRole(
                actorUserId,
                new AdminOperationsDto.CreateRoleRequest("ROLE_MEDIA_CURATOR", "媒体策展人", null, "superadmin")))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.PARAM_ERROR);
    }

    @Test
    void createRoleRejectsMissingTemplateRole() {
        givenFreshAdminActor();
        when(authRoleRepository.existsByCode("ROLE_MEDIA_CURATOR")).thenReturn(false);
        when(authRoleRepository.findWithPermissionsByCode(Roles.MEMBER)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.createRole(
                actorUserId,
                new AdminOperationsDto.CreateRoleRequest("ROLE_MEDIA_CURATOR", "媒体策展人", null, "member")))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.INTERNAL_ERROR);
    }

    @Test
    void deleteRoleRemovesCustomRoleAndClearsPermissionBindings() {
        givenFreshAdminActor();
        AuthRole custom = role("ROLE_MEDIA_CURATOR",
                permission(Permissions.SYSTEM_USER_READ, "system"),
                permission(Permissions.SYSTEM_USER_MANAGE, "system"));
        custom.setBuiltIn(false);
        when(authRoleRepository.findWithPermissionsByCode("ROLE_MEDIA_CURATOR")).thenReturn(Optional.of(custom));
        when(authUserRepository.existsByRoles_Code("ROLE_MEDIA_CURATOR")).thenReturn(false);

        service.deleteRole(actorUserId, "role_media_curator");

        assertThat(custom.getPermissions()).isEmpty();
        verify(authRoleRepository).delete(custom);
        ArgumentCaptor<Map<String, Object>> payloadCaptor = ArgumentCaptor.captor();
        verify(auditLogService).recordWithPayload(
                eq(actorUserId), eq("ADMIN_ROLE_DELETE"), eq("auth_roles"), eq(custom.getId()),
                payloadCaptor.capture());
        assertThat(payloadCaptor.getValue())
                .containsEntry("code", "ROLE_MEDIA_CURATOR")
                .containsEntry("permissionCount", 2);
    }

    @Test
    void deleteRoleRejectsBuiltinRole() {
        givenFreshAdminActor();
        AuthRole builtin = role(Roles.ADMIN, permission(Permissions.SYSTEM_USER_READ, "system"));
        when(authRoleRepository.findWithPermissionsByCode(Roles.ADMIN)).thenReturn(Optional.of(builtin));

        assertThatThrownBy(() -> service.deleteRole(actorUserId, Roles.ADMIN))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.FORBIDDEN);
        verify(authRoleRepository, never()).delete(any(AuthRole.class));
    }

    @Test
    void deleteRoleRejectsRoleWithBoundUsers() {
        givenFreshAdminActor();
        AuthRole custom = role("ROLE_MEDIA_CURATOR");
        custom.setBuiltIn(false);
        when(authRoleRepository.findWithPermissionsByCode("ROLE_MEDIA_CURATOR")).thenReturn(Optional.of(custom));
        when(authUserRepository.existsByRoles_Code("ROLE_MEDIA_CURATOR")).thenReturn(true);

        assertThatThrownBy(() -> service.deleteRole(actorUserId, "ROLE_MEDIA_CURATOR"))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("解绑")
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.RESOURCE_IN_USE);
        verify(authRoleRepository, never()).delete(any(AuthRole.class));
    }

    @Test
    void deleteRoleRejectsMissingRole() {
        givenFreshAdminActor();
        when(authRoleRepository.findWithPermissionsByCode("ROLE_GONE")).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.deleteRole(actorUserId, "ROLE_GONE"))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.NOT_FOUND);
    }

    private AuthRole role(String code, AuthPermission... permissions) {
        AuthRole role = new AuthRole();
        role.setId(UUID.randomUUID());
        role.setCode(code);
        role.setName(code);
        role.getPermissions().addAll(List.of(permissions));
        return role;
    }

    private AuthPermission permission(String code, String module) {
        AuthPermission permission = new AuthPermission();
        permission.setId(UUID.randomUUID());
        permission.setCode(code);
        permission.setName(code);
        permission.setModule(module);
        return permission;
    }
}
