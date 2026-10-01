package com.omninest.modules.user.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.security.CurrentUserContext;
import com.omninest.common.security.Roles;
import java.util.List;

import com.omninest.modules.notification.port.NotificationMaintenance;
import com.omninest.modules.preferences.service.UserPreferenceService;
import com.omninest.modules.quota.service.StorageQuotaReservationService;
import com.omninest.modules.user.domain.AuthRole;
import com.omninest.modules.user.domain.AuthUser;
import com.omninest.modules.user.repository.ActiveSessionRepository;
import com.omninest.modules.user.repository.AdminUserContentGuardRepository;
import com.omninest.modules.user.repository.AuthBackupCodeRepository;
import com.omninest.modules.user.repository.AuthTotpCredentialRepository;
import com.omninest.modules.user.repository.AuthUserRepository;
import com.omninest.modules.user.service.UserSessionRevocationService;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.Mockito;

class AdminUserDeletionServiceTest {
    private final AuthUserRepository authUserRepository = Mockito.mock(AuthUserRepository.class);
    private final ActiveSessionRepository activeSessionRepository = Mockito.mock(ActiveSessionRepository.class);
    private final UserSessionRevocationService userSessionRevocationService =
            Mockito.mock(UserSessionRevocationService.class);
    private final AuthTotpCredentialRepository authTotpCredentialRepository =
            Mockito.mock(AuthTotpCredentialRepository.class);
    private final AuthBackupCodeRepository authBackupCodeRepository =
            Mockito.mock(AuthBackupCodeRepository.class);
    private final StorageQuotaReservationService storageQuotaReservationService =
            Mockito.mock(StorageQuotaReservationService.class);
    private final UserPreferenceService userPreferenceService =
            Mockito.mock(UserPreferenceService.class);
    private final NotificationMaintenance notificationService = Mockito.mock(NotificationMaintenance.class);
    private final AdminUserContentGuardRepository adminUserContentGuardRepository =
            Mockito.mock(AdminUserContentGuardRepository.class);
    private final AdminAuditLogService auditLogService = Mockito.mock(AdminAuditLogService.class);
    private final CurrentUserContext currentUserContext = Mockito.mock(CurrentUserContext.class);
    private final AdminUserDeletionService service = new AdminUserDeletionService(
            authUserRepository,
            activeSessionRepository,
            userSessionRevocationService,
            authTotpCredentialRepository,
            authBackupCodeRepository,
            storageQuotaReservationService,
            userPreferenceService,
            notificationService,
            adminUserContentGuardRepository,
            auditLogService,
            currentUserContext
    );

    private final UUID actorUserId = UUID.fromString("99999999-9999-9999-9999-999999999999");
    private final UUID targetUserId = UUID.fromString("10000000-0000-0000-0000-000000000001");

    private void givenActor() {
        when(currentUserContext.requireCurrentUserId()).thenReturn(actorUserId);
    }

    private AuthUser targetUser(String roleCode) {
        AuthUser user = new AuthUser();
        user.setId(targetUserId);
        user.setUsername("member-it");
        user.setPasswordHash("hash");
        if (roleCode != null) {
            AuthRole role = new AuthRole();
            role.setId(UUID.randomUUID());
            role.setCode(roleCode);
            role.setName(roleCode);
            user.getRoles().add(role);
        }
        return user;
    }

    @Test
    void deleteUserRejectsSelfDeletion() {
        givenActor();

        assertThatThrownBy(() -> service.deleteUser(actorUserId))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.FORBIDDEN);
        verifyNoInteractions(authUserRepository, notificationService, auditLogService);
    }

    @Test
    void deleteUserRejectsMissingUser() {
        givenActor();
        when(authUserRepository.findWithRolesById(targetUserId)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.deleteUser(targetUserId))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.NOT_FOUND);
    }

    @Test
    void deleteUserRejectsSuperAdmin() {
        givenActor();
        when(authUserRepository.findWithRolesById(targetUserId))
                .thenReturn(Optional.of(targetUser(Roles.SUPER_ADMIN)));

        assertThatThrownBy(() -> service.deleteUser(targetUserId))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.FORBIDDEN);
        verifyNoInteractions(notificationService, activeSessionRepository, auditLogService);
    }

    @Test
    void deleteUserRejectsUserWithUnclearedStorageUsage() {
        givenActor();
        AuthUser user = targetUser(Roles.MEMBER);
        user.setUsedBytes(1024L);
        when(authUserRepository.findWithRolesById(targetUserId)).thenReturn(Optional.of(user));

        assertThatThrownBy(() -> service.deleteUser(targetUserId))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.RESOURCE_IN_USE);
        verifyNoInteractions(notificationService, activeSessionRepository, auditLogService);
    }

    @Test
    void deleteUserRejectsUserOwningBusinessContent() {
        givenActor();
        when(authUserRepository.findWithRolesById(targetUserId))
                .thenReturn(Optional.of(targetUser(Roles.MEMBER)));
        when(adminUserContentGuardRepository.countOwnedContent(targetUserId))
                .thenReturn(Map.of("文件", 3L, "照片", 1L));

        assertThatThrownBy(() -> service.deleteUser(targetUserId))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("文件")
                .hasMessageContaining("照片")
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.RESOURCE_IN_USE);
        verifyNoInteractions(notificationService, activeSessionRepository, auditLogService);
    }

    @Test
    void deleteUserPhysicallyRemovesEmptyAccountAndKeepsAudit() {
        givenActor();
        AuthUser user = targetUser(Roles.MEMBER);
        when(authUserRepository.findWithRolesById(targetUserId)).thenReturn(Optional.of(user));
        when(adminUserContentGuardRepository.countOwnedContent(targetUserId)).thenReturn(Map.of());

        service.deleteUser(targetUserId);

        verify(notificationService).adminPurgeForUser(targetUserId);
        verify(userPreferenceService).adminPurgeForUser(targetUserId);
        verify(storageQuotaReservationService).adminPurgeForUser(targetUserId);
        verify(authTotpCredentialRepository).deleteByUserId(targetUserId);
        verify(authBackupCodeRepository).deleteByUserId(targetUserId);
        verify(activeSessionRepository).deleteByUserId(targetUserId);
        verify(userSessionRevocationService).revokeAll(List.of(targetUserId), "管理员删除用户");
        assertThat(user.getRoles()).isEmpty();
        verify(authUserRepository).delete(user);
        ArgumentCaptor<Map<String, Object>> payloadCaptor = ArgumentCaptor.forClass(Map.class);
        verify(auditLogService).recordWithPayload(
                eq(actorUserId), eq("ADMIN_USER_DELETE"), eq("auth_users"), eq(targetUserId),
                payloadCaptor.capture());
        assertThat(payloadCaptor.getValue()).containsEntry("username", "member-it");
    }
}
