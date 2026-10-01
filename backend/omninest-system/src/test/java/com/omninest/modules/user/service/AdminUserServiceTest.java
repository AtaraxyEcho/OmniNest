package com.omninest.modules.user.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.security.CurrentUserContext;
import com.omninest.modules.quota.service.StorageQuotaService;
import com.omninest.modules.user.domain.AuthRole;
import com.omninest.modules.user.domain.AuthTotpCredential;
import com.omninest.modules.user.domain.AuthUser;
import com.omninest.modules.user.dto.AuthUserDto;
import com.omninest.modules.user.repository.AuthRoleRepository;
import com.omninest.modules.user.repository.AuthTotpCredentialRepository;
import com.omninest.modules.user.repository.AuthUserRepository;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Sort;
import org.springframework.security.crypto.password.PasswordEncoder;

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
    private final AdminUserService service = new AdminUserService(
            authUserRepository,
            authRoleRepository,
            authTotpCredentialRepository,
            passwordEncoder,
            passwordPolicy,
            auditLogService,
            currentUserContext,
            storageQuotaService,
            userSessionRevocationService
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
        UUID userId = UUID.fromString("10000000-0000-0000-0000-000000000002");
        UUID customRoleId = UUID.fromString("53e2e138-59b7-4fa6-988f-58554f34b8d4");
        AuthUser user = new AuthUser();
        user.setId(userId);
        user.setUsername("bob");
        user.setPasswordHash("hash");
        when(authUserRepository.findWithRolesById(userId)).thenReturn(java.util.Optional.of(user));
        when(authUserRepository.save(any(AuthUser.class))).thenAnswer(invocation -> invocation.getArgument(0));
        when(authRoleRepository.findByCode("ROLE_MEDIA_OPERATOR"))
                .thenReturn(java.util.Optional.of(role(customRoleId, "ROLE_MEDIA_OPERATOR")));

        AuthUserDto saved = service.updateUserRoles(userId, java.util.Set.of("role_media_operator"));

        assertThat(saved.roles()).containsExactly("ROLE_MEDIA_OPERATOR");

        when(authRoleRepository.findByCode("ROLE_GHOST")).thenReturn(java.util.Optional.empty());
        assertThatThrownBy(() -> service.updateUserRoles(userId, java.util.Set.of("ROLE_GHOST")))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.PARAM_ERROR);
        assertThatThrownBy(() -> service.updateUserRoles(userId, java.util.Set.of("SUPER_ADMIN")))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.FORBIDDEN);
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
        when(authUserRepository.findWithRolesById(okId)).thenReturn(java.util.Optional.of(member));
        when(authUserRepository.findWithRolesById(missingId)).thenReturn(java.util.Optional.empty());
        when(authUserRepository.findWithRolesById(superAdminId)).thenReturn(java.util.Optional.of(superAdmin));
        when(authUserRepository.save(any(AuthUser.class))).thenAnswer(invocation -> invocation.getArgument(0));
        when(currentUserContext.requireCurrentUserId()).thenReturn(okId);

        var result = service.batchUpdateUserStatus(
                java.util.List.of(okId, missingId, superAdminId), "DISABLED");

        assertThat(result.successCount()).isEqualTo(1);
        assertThat(result.failedIds()).containsExactly(missingId, superAdminId);
        assertThat(member.getStatus()).isEqualTo("DISABLED");
        verify(userSessionRevocationService).revokeAll(java.util.List.of(okId), "管理员更新用户状态");
        verify(auditLogService).recordWithMetadata(
                eq(okId), eq("ADMIN_USER_STATUS_UPDATE"), eq("auth_users"), eq(okId), any());
    }

    @Test
    void batchUpdateUserStatusRejectsIllegalStatusUpFront() {
        assertThatThrownBy(() -> service.batchUpdateUserStatus(
                java.util.List.of(UUID.randomUUID()), "PAUSED"))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.PARAM_ERROR);
    }

    private AuthRole role(UUID id, String code) {
        AuthRole role = new AuthRole();
        role.setId(id);
        role.setCode(code);
        role.setName(code);
        return role;
    }
}
