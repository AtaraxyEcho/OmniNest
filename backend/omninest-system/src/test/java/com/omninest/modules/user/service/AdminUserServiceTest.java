package com.omninest.modules.user.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.security.CurrentUserContext;
import com.omninest.common.storage.ObjectStorageBuckets;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.common.security.Permissions;
import com.omninest.common.security.Roles;
import com.omninest.modules.quota.service.StorageQuotaService;
import com.omninest.modules.user.domain.AuthPermission;
import com.omninest.modules.user.domain.AuthRole;
import com.omninest.modules.user.domain.AuthTotpCredential;
import com.omninest.modules.user.domain.AuthUser;
import com.omninest.modules.user.dto.AuthUserDto;
import com.omninest.modules.user.repository.AuthRoleRepository;
import com.omninest.modules.user.repository.AuthTotpCredentialRepository;
import com.omninest.modules.user.repository.AuthUserRepository;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Sort;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

class AdminUserServiceTest {
    private final AuthUserRepository authUserRepository = mock(AuthUserRepository.class);
    private final AuthRoleRepository authRoleRepository = mock(AuthRoleRepository.class);
    private final AuthTotpCredentialRepository authTotpCredentialRepository =
            mock(AuthTotpCredentialRepository.class);
    private final PasswordEncoder passwordEncoder = mock(PasswordEncoder.class);
    private final PasswordPolicy passwordPolicy = mock(PasswordPolicy.class);
    private final AdminAuditLogService auditLogService = mock(AdminAuditLogService.class);
    private final CurrentUserContext currentUserContext = mock(CurrentUserContext.class);
    private final StorageQuotaService storageQuotaService = mock(StorageQuotaService.class);
    private final UserSessionRevocationService userSessionRevocationService =
            mock(UserSessionRevocationService.class);
    private final TwoFactorService twoFactorService = mock(TwoFactorService.class);
    private final AdminActorGuard adminActorGuard = new AdminActorGuard(authUserRepository);
    private final CurrentUserService currentUserService = mock(CurrentUserService.class);
    private final TransactionTemplate transactionTemplate =
            new TransactionTemplate(mock(PlatformTransactionManager.class));
    private final ObjectStorageClient objectStorageClient = mock(ObjectStorageClient.class);
    private final ObjectStorageBuckets objectStorageBuckets = mock(ObjectStorageBuckets.class);
    private final AdminUserService service = new AdminUserService(
            authUserRepository,
            authRoleRepository,
            authTotpCredentialRepository,
            passwordEncoder,
            passwordPolicy,
            auditLogService,
            currentUserContext,
            storageQuotaService,
            userSessionRevocationService,
            twoFactorService,
            adminActorGuard,
            currentUserService,
            transactionTemplate,
            objectStorageClient,
            objectStorageBuckets
    );

    @Test
    void listUsersNormalizesQueryAndRoleFilter() {
        UUID roleId = UUID.fromString("53e2e138-59b7-4fa6-988f-58554f34b8d3");
        AuthRole memberRole = role(roleId, "MEMBER");
        AuthUser user = new AuthUser();
        user.setId(UUID.fromString("10000000-0000-0000-0000-000000000001"));
        user.setUsername("alice");
        user.setPasswordHash("hash");
        user.getRoles().add(memberRole);
        Page<AuthUser> page = new PageImpl<>(List.of(user), PageRequest.of(0, 50), 1);
        when(authUserRepository.searchAdminUsers(eq("%alice%"), eq("ADMIN"), any(PageRequest.class)))
                .thenReturn(page);
        when(authRoleRepository.findPermissionCodesByRoleIds(any()))
                .thenReturn(Map.of(roleId, Set.of("system:user:read")));

        Page<AuthUserDto> result = service.listUsers(0, 50, " Alice ", "admin", "username", "asc");

        assertThat(result.getContent()).hasSize(1);
        assertThat(result.getContent().get(0).username()).isEqualTo("alice");
        assertThat(result.getContent().get(0).roles()).containsExactly("MEMBER");
        assertThat(result.getContent().get(0).permissions()).containsExactly("system:user:read");
        assertThat(result.getContent().get(0).twoFactorEnabled()).isFalse();
        ArgumentCaptor<PageRequest> pageableCaptor = ArgumentCaptor.forClass(PageRequest.class);
        verify(authUserRepository).searchAdminUsers(eq("%alice%"), eq("ADMIN"), pageableCaptor.capture());
        assertThat(pageableCaptor.getValue().getSort())
                .isEqualTo(Sort.by(Sort.Direction.ASC, "username").and(Sort.by(Sort.Direction.DESC, "id")));
        assertThat(pageableCaptor.getValue().getPageSize()).isEqualTo(50);
    }

    @Test
    void listUsersAppliesWhitelistedSortAndFallsBackToUsername() {
        when(authUserRepository.searchAdminUsers(eq(""), eq(""), any(PageRequest.class)))
                .thenReturn(Page.empty());

        service.listUsers(0, 50, "", "ALL", "usedBytes", "desc");

        ArgumentCaptor<PageRequest> descCaptor = ArgumentCaptor.forClass(PageRequest.class);
        verify(authUserRepository).searchAdminUsers(eq(""), eq(""), descCaptor.capture());
        assertThat(descCaptor.getValue().getSort())
                .isEqualTo(Sort.by(Sort.Direction.DESC, "usedBytes").and(Sort.by(Sort.Direction.DESC, "id")));

        service.listUsers(0, 50, "", "ALL", "passwordHash; drop table", "desc");

        ArgumentCaptor<PageRequest> fallbackCaptor = ArgumentCaptor.forClass(PageRequest.class);
        verify(authUserRepository, times(2))
                .searchAdminUsers(eq(""), eq(""), fallbackCaptor.capture());
        assertThat(fallbackCaptor.getAllValues().get(1).getSort().getOrderFor("username")).isNotNull();
        assertThat(fallbackCaptor.getAllValues().get(1).getSort().getOrderFor("passwordHash")).isNull();
    }

    @Test
    void listUsersMapsTwoFactorEnabledFromBatchQuery() {
        UUID userId = UUID.fromString("10000000-0000-0000-0000-00000000000f");
        AuthUser user = new AuthUser();
        user.setId(userId);
        user.setUsername("alice");
        user.setPasswordHash("hash");
        Page<AuthUser> page = new PageImpl<>(List.of(user), PageRequest.of(0, 50), 1);
        when(authUserRepository.searchAdminUsers(eq(""), eq(""), any(PageRequest.class)))
                .thenReturn(page);
        when(authRoleRepository.findPermissionCodesByRoleIds(any())).thenReturn(Map.of());
        AuthTotpCredential credential = new AuthTotpCredential();
        credential.setUserId(userId);
        when(authTotpCredentialRepository.findByUserIdInAndEnabledTrue(List.of(userId)))
                .thenReturn(List.of(credential));

        Page<AuthUserDto> result = service.listUsers(0, 50, "", "ALL", "username", "asc");

        assertThat(result.getContent().get(0).twoFactorEnabled()).isTrue();
    }

    @Test
    void listUsersTreatsAllRoleAndBlankQueryAsNoFilter() {
        when(authUserRepository.searchAdminUsers(eq(""), eq(""), any(PageRequest.class)))
                .thenReturn(Page.empty());

        service.listUsers(0, 50, "   ", "ALL", "username", "asc");

        verify(authUserRepository).searchAdminUsers(eq(""), eq(""), any(PageRequest.class));
    }

    @Test
    void listUsersRejectsOverlongSearchOrFilter() {
        assertThatThrownBy(() -> service.listUsers(0, 50, "x".repeat(201), "", "username", "asc"))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.PARAM_ERROR);
        assertThatThrownBy(() -> service.listUsers(0, 50, "", "R".repeat(101), "username", "asc"))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.PARAM_ERROR);
    }

    @Test
    void updateUserRolesAcceptsExistingCustomRoleAndRejectsUnknownOrSuperAdmin() {
        givenSuperAdminActor();
        UUID userId = UUID.fromString("10000000-0000-0000-0000-000000000002");
        UUID customRoleId = UUID.fromString("53e2e138-59b7-4fa6-988f-58554f34b8d4");
        AuthUser user = new AuthUser();
        user.setId(userId);
        user.setUsername("bob");
        user.setPasswordHash("hash");
        when(authUserRepository.findWithRolesById(userId)).thenReturn(Optional.of(user));
        when(authUserRepository.save(any(AuthUser.class))).thenAnswer(invocation -> invocation.getArgument(0));
        when(authRoleRepository.findByCode("ROLE_MEDIA_OPERATOR"))
                .thenReturn(Optional.of(role(customRoleId, "ROLE_MEDIA_OPERATOR")));

        AuthUserDto saved = service.updateUserRoles(userId, Set.of("role_media_operator"));

        assertThat(saved.roles()).containsExactly("ROLE_MEDIA_OPERATOR");

        when(authRoleRepository.findByCode("ROLE_GHOST")).thenReturn(Optional.empty());
        assertThatThrownBy(() -> service.updateUserRoles(userId, Set.of("ROLE_GHOST")))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.PARAM_ERROR);
        assertThatThrownBy(() -> service.updateUserRoles(userId, Set.of("SUPER_ADMIN")))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.FORBIDDEN);
    }

    @Test
    void updateUserStatusRejectsDisablingSelf() {
        UUID actorId = UUID.fromString("10000000-0000-0000-0000-00000000000e");
        givenActorAs(actorId, Roles.SUPER_ADMIN);
        AuthUser self = new AuthUser();
        self.setId(actorId);
        self.setUsername("admin-self");
        self.getRoles().add(role(UUID.randomUUID(), Roles.ADMIN));
        when(authUserRepository.findWithRolesById(actorId)).thenReturn(Optional.of(self));

        assertThatThrownBy(() -> service.updateUserStatus(actorId, "DISABLED"))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("不能禁用当前登录的管理员账号");
    }

    @Test
    void updateUserRolesRejectsRemovingOwnAdminRole() {
        UUID actorId = UUID.fromString("10000000-0000-0000-0000-00000000000f");
        givenActorAs(actorId, Roles.SUPER_ADMIN);
        AuthUser self = new AuthUser();
        self.setId(actorId);
        self.setUsername("admin-self");
        self.getRoles().add(role(UUID.randomUUID(), Roles.ADMIN));
        when(authUserRepository.findWithRolesById(actorId)).thenReturn(Optional.of(self));
        when(authRoleRepository.findByCode("MEMBER")).thenReturn(Optional.of(role(UUID.randomUUID(), "MEMBER")));

        assertThatThrownBy(() -> service.updateUserRoles(actorId, Set.of("MEMBER")))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("不能移除当前登录账号的管理员角色");
    }

    @Test
    void batchUpdateUserStatusSkipsFailuresAndReturnsPerItemResult() {
        UUID okId = UUID.fromString("10000000-0000-0000-0000-00000000000a");
        UUID missingId = UUID.fromString("10000000-0000-0000-0000-00000000000b");
        UUID superAdminId = UUID.fromString("10000000-0000-0000-0000-00000000000c");
        AuthUser member = new AuthUser();
        member.setId(okId);
        member.setUsername("member-1");
        AuthUser superAdmin = new AuthUser();
        superAdmin.setId(superAdminId);
        superAdmin.setUsername("root");
        superAdmin.getRoles().add(role(UUID.randomUUID(), "SUPER_ADMIN"));
        when(authUserRepository.findWithRolesById(okId)).thenReturn(Optional.of(member));
        when(authUserRepository.findWithRolesById(missingId)).thenReturn(Optional.empty());
        when(authUserRepository.findWithRolesById(superAdminId)).thenReturn(Optional.of(superAdmin));
        when(authUserRepository.save(any(AuthUser.class))).thenAnswer(invocation -> invocation.getArgument(0));
        // 操作者与目标分离：自身状态变更是另一条自锁用例，批量这里验证逐项成功/失败。
        givenActorAs(UUID.fromString("10000000-0000-0000-0000-00000000000d"), Roles.SUPER_ADMIN);

        var result = service.batchUpdateUserStatus(
                List.of(okId, missingId, superAdminId), "DISABLED");

        assertThat(result.successCount()).isEqualTo(1);
        assertThat(result.failedIds()).containsExactly(missingId, superAdminId);
        assertThat(member.getStatus()).isEqualTo("DISABLED");
        verify(userSessionRevocationService).revokeAll(List.of(okId), "管理员更新用户状态");
        verify(auditLogService).recordWithMetadata(
                eq(UUID.fromString("10000000-0000-0000-0000-00000000000d")),
                eq("ADMIN_USER_STATUS_UPDATE"), eq("auth_users"), eq(okId), any());
    }

    @Test
    void batchUpdateUserStatusRejectsIllegalStatusUpFront() {
        assertThatThrownBy(() -> service.batchUpdateUserStatus(
                List.of(UUID.randomUUID()), "PAUSED"))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.PARAM_ERROR);
    }

    @Test
    void resetTwoFactorClearsCredentialsAndRevokesSessions() {
        UUID adminId = UUID.fromString("20000000-0000-0000-0000-000000000002");
        UUID targetId = UUID.fromString("30000000-0000-0000-0000-000000000003");
        AuthUser target = new AuthUser();
        target.setId(targetId);
        target.setUsername("alice");
        when(authUserRepository.findWithRolesById(targetId)).thenReturn(Optional.of(target));
        givenActorAs(adminId, Roles.ADMIN);

        service.resetTwoFactor(targetId);

        verify(twoFactorService).resetByAdmin(targetId);
        verify(userSessionRevocationService).revokeAll(List.of(targetId), "管理员重置两步验证");
        verify(auditLogService).recordWithMetadata(
                adminId, "ADMIN_USER_2FA_RESET", "auth_users", targetId, Map.of("username", "alice"));
    }

    @Test
    void resetTwoFactorAlsoWorksForSuperAdminTarget() {
        UUID superAdminId = UUID.fromString("40000000-0000-0000-0000-000000000004");
        AuthRole superAdminRole = role(
                UUID.fromString("4e302a1e-3af2-4e23-8702-5475f5448025"), Roles.SUPER_ADMIN);
        AuthUser target = new AuthUser();
        target.setId(superAdminId);
        target.setUsername("root");
        target.getRoles().add(superAdminRole);
        when(authUserRepository.findWithRolesById(superAdminId)).thenReturn(Optional.of(target));
        givenActorAs(superAdminId, Roles.SUPER_ADMIN);

        service.resetTwoFactor(superAdminId);

        verify(twoFactorService).resetByAdmin(superAdminId);
    }

    @Test
    void resetTwoFactorRejectsMissingUserWithoutSideEffects() {
        UUID missingId = UUID.fromString("50000000-0000-0000-0000-000000000005");
        givenActorAs(UUID.fromString("20000000-0000-0000-0000-000000000009"), Roles.ADMIN);
        when(authUserRepository.findWithRolesById(missingId)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.resetTwoFactor(missingId))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.NOT_FOUND);
        verifyNoInteractions(twoFactorService, userSessionRevocationService, auditLogService);
    }

    /** 普通管理员不能停用同级管理员。 */
    @Test
    void updateUserStatusRejectsAdminTargetForPlainAdminActor() {
        UUID actorId = UUID.fromString("20000000-0000-0000-0000-000000000007");
        UUID peerId = UUID.fromString("10000000-0000-0000-0000-00000000000d");
        givenActorAs(actorId, Roles.ADMIN);
        AuthUser peer = new AuthUser();
        peer.setId(peerId);
        peer.setUsername("peer-admin");
        peer.getRoles().add(role(UUID.randomUUID(), Roles.ADMIN));
        when(authUserRepository.findWithRolesById(peerId)).thenReturn(Optional.of(peer));

        assertThatThrownBy(() -> service.updateUserStatus(peerId, "DISABLED"))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("仅超级管理员可修改管理员账户状态");
        verifyNoInteractions(auditLogService);
    }

    /** 普通管理员不能把管理员角色授予别人。 */
    @Test
    void updateUserRolesRejectsAdminRoleForPlainAdminActor() {
        UUID actorId = UUID.fromString("20000000-0000-0000-0000-000000000008");
        UUID userId = UUID.fromString("10000000-0000-0000-0000-00000000000e");
        givenActorAs(actorId, Roles.ADMIN);
        AuthUser user = new AuthUser();
        user.setId(userId);
        user.setUsername("bob");
        when(authUserRepository.findWithRolesById(userId)).thenReturn(Optional.of(user));
        when(authRoleRepository.findByCode(Roles.ADMIN))
                .thenReturn(Optional.of(role(UUID.randomUUID(), Roles.ADMIN)));

        assertThatThrownBy(() -> service.updateUserRoles(userId, Set.of(Roles.ADMIN)))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("仅超级管理员可授予管理员角色");
    }

    /** 自定义角色的权限集合超出操作者自身权限时拒绝，阻断自助造高权账户。 */
    @Test
    void updateUserRolesRejectsGrantBeyondActorPermissions() {
        UUID actorId = UUID.fromString("20000000-0000-0000-0000-000000000011");
        UUID userId = UUID.fromString("10000000-0000-0000-0000-000000000012");
        UUID roleId = UUID.fromString("53e2e138-59b7-4fa6-988f-58554f34b8d5");
        givenActorAs(actorId, Roles.ADMIN, permission(Permissions.FILE_READ, "file"));
        AuthUser user = new AuthUser();
        user.setId(userId);
        user.setUsername("bob");
        when(authUserRepository.findWithRolesById(userId)).thenReturn(Optional.of(user));
        when(authRoleRepository.findByCode("ROLE_AUDITOR"))
                .thenReturn(Optional.of(role(roleId, "ROLE_AUDITOR")));
        when(authRoleRepository.findPermissionCodesByRoleIds(any()))
                .thenReturn(Map.of(roleId, Set.of(Permissions.SYSTEM_USER_MANAGE)));

        assertThatThrownBy(() -> service.updateUserRoles(userId, Set.of("ROLE_AUDITOR")))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("不能授予操作者自身不具备的权限");
    }

    private void givenSuperAdminActor() {
        givenActorAs(UUID.fromString("20000000-0000-0000-0000-0000000000f0"), Roles.SUPER_ADMIN);
    }

    /** 把操作者装成指定角色的活跃管理员：写操作入口都要按库内当前身份复核。 */
    private void givenActorAs(UUID actorId, String roleCode, AuthPermission... permissions) {
        when(currentUserContext.requireCurrentUserId()).thenReturn(actorId);
        AuthUser actor = new AuthUser();
        actor.setId(actorId);
        actor.setUsername("admin-it");
        actor.setStatus("ACTIVE");
        AuthRole role = role(UUID.randomUUID(), roleCode);
        role.getPermissions().addAll(List.of(permissions));
        actor.getRoles().add(role);
        when(authUserRepository.findWithRolesAndPermissionsById(actorId)).thenReturn(Optional.of(actor));
    }

    private AuthPermission permission(String code, String module) {
        AuthPermission permission = new AuthPermission();
        permission.setId(UUID.randomUUID());
        permission.setCode(code);
        permission.setName(code);
        permission.setModule(module);
        return permission;
    }

    private AuthRole role(UUID id, String code) {
        AuthRole role = new AuthRole();
        role.setId(id);
        role.setCode(code);
        role.setName(code);
        return role;
    }
}
