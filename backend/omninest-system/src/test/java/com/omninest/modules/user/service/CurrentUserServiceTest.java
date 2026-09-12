package com.omninest.modules.user.service;

import java.util.function.Supplier;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.omninest.common.cache.ReadThroughCache;
import com.omninest.common.security.CurrentUserContext;
import com.omninest.common.security.MalwareScanGateway;
import com.omninest.common.security.Permissions;
import com.omninest.common.security.Roles;
import com.omninest.common.storage.ObjectStorageBuckets;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.user.domain.AuthActiveSession;
import com.omninest.modules.user.domain.AuthPermission;
import com.omninest.modules.user.domain.AuthRole;
import com.omninest.modules.user.domain.AuthUser;
import com.omninest.modules.notification.service.NotificationService;
import com.omninest.modules.user.repository.ActiveSessionRepository;
import com.omninest.modules.user.repository.AuthUserRepository;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.security.crypto.password.PasswordEncoder;

/**
 * 当前用户服务测试。
 *
 * @author OmniNest
 */
class CurrentUserServiceTest {
    private final AuthUserRepository authUserRepository = mock(AuthUserRepository.class);
    private final ActiveSessionRepository activeSessionRepository = mock(ActiveSessionRepository.class);
    private final CurrentUserContext currentUserContext = mock(CurrentUserContext.class);
    private final PasswordEncoder passwordEncoder = mock(PasswordEncoder.class);
    private final ObjectStorageClient objectStorageClient = mock(ObjectStorageClient.class);
    private final ObjectStorageBuckets objectStorageBuckets = createObjectStorageBuckets();
    private final NotificationService notificationService = mock(NotificationService.class);
    private final SessionRevocationService sessionRevocationService = mock(SessionRevocationService.class);
    private final ReadThroughCache readThroughCache = mock(ReadThroughCache.class, invocation -> {
        if ("getOrLoad".equals(invocation.getMethod().getName())) {
            Supplier<?> loader = invocation.getArgument(2);
            return loader.get();
        }
        return null;
    });
    private final MalwareScanGateway malwareScanGateway = mock(MalwareScanGateway.class);
    private final CurrentUserService service = new CurrentUserService(
            authUserRepository, activeSessionRepository, currentUserContext, passwordEncoder,
            new PasswordPolicy(), objectStorageClient, objectStorageBuckets, notificationService, sessionRevocationService,
            readThroughCache, malwareScanGateway);

    @Test
    void returnsCurrentUserFromSecurityContextUserId() {
        UUID userId = UUID.fromString("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
        AuthUser existing = new AuthUser();
        existing.setId(userId);
        existing.setUsername("root");
        existing.setDisplayName("Root");
        existing.setEmail("root@example.com");
        existing.getRoles().add(role("ADMIN", Permissions.SYSTEM_CONFIG_MANAGE));
        existing.setQuotaBytes(2048L);
        existing.setUsedBytes(128L);
        when(currentUserContext.requireCurrentUserId()).thenReturn(userId);
        when(authUserRepository.findWithRolesById(userId)).thenReturn(Optional.of(existing));

        var profile = service.currentUser();

        assertThat(profile.id()).isEqualTo(userId);
        assertThat(profile.username()).isEqualTo("root");
        assertThat(profile.role()).isEqualTo("ADMIN");
        assertThat(profile.roles()).containsExactly("ADMIN");
        assertThat(profile.permissions()).containsExactly(Permissions.SYSTEM_CONFIG_MANAGE);
        assertThat(profile.quotaBytes()).isEqualTo(2048L);
        assertThat(profile.usedBytes()).isEqualTo(128L);
    }

    @Test
    void returnsDatabaseSuperAdmin() {
        UUID userId = UUID.fromString("00000000-0000-0000-0000-000000000001");
        AuthUser existing = new AuthUser();
        existing.setId(userId);
        existing.setUsername("root");
        existing.setDisplayName("超级管理员");
        existing.setEmail("administrator@example.com");
        existing.getRoles().add(role(Roles.SUPER_ADMIN, Permissions.SYSTEM_USER_MANAGE));
        when(currentUserContext.requireCurrentUserId()).thenReturn(userId);
        when(authUserRepository.findWithRolesById(userId)).thenReturn(Optional.of(existing));

        var profile = service.currentUser();

        assertThat(profile.id()).isEqualTo(userId);
        assertThat(profile.username()).isEqualTo("root");
        assertThat(profile.role()).isEqualTo(Roles.SUPER_ADMIN);
        assertThat(profile.roles()).containsExactly(Roles.SUPER_ADMIN);
        assertThat(profile.permissions()).containsExactly(Permissions.SYSTEM_USER_MANAGE);
    }

    @Test
    void returnsActiveSessionsForUser() {
        UUID userId = UUID.randomUUID();
        AuthActiveSession session = new AuthActiveSession();
        session.setId(UUID.randomUUID());
        session.setUserId(userId);
        when(activeSessionRepository.findByUserIdAndRevokedAtIsNullOrderByCreatedAtDesc(userId))
                .thenReturn(List.of(session));

        List<AuthActiveSession> result = service.activeSessions(userId);

        assertThat(result).containsExactly(session);
    }

    @Test
    void rejectsMissingCurrentUserRecord() {
        UUID userId = UUID.fromString("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
        when(currentUserContext.requireCurrentUserId()).thenReturn(userId);
        when(authUserRepository.findWithRolesById(userId)).thenReturn(Optional.empty());

        assertThatThrownBy(service::currentUser)
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("当前用户不存在");
    }

    @Test
    void changePassword_wrongOldPassword_throws() {
        UUID userId = UUID.randomUUID();
        AuthUser user = new AuthUser();
        user.setPasswordHash("$2a$10$encodedOld");
        when(authUserRepository.findById(userId)).thenReturn(Optional.of(user));
        when(passwordEncoder.matches("wrong", "$2a$10$encodedOld")).thenReturn(false);

        assertThatThrownBy(() ->
                service.changePassword(userId, "wrong", "newPass123")
        ).isInstanceOf(BusinessException.class)
                .hasMessageContaining("原密码错误");
    }

    @Test
    void changePassword_shortNewPassword_throws() {
        UUID userId = UUID.randomUUID();
        AuthUser user = new AuthUser();
        user.setUsername("reader");
        user.setPasswordHash("$2a$10$oldHash");
        when(authUserRepository.findById(userId)).thenReturn(Optional.of(user));
        when(passwordEncoder.matches("oldPass", "$2a$10$oldHash")).thenReturn(true);

        assertThatThrownBy(() ->
                service.changePassword(userId, "oldPass", "123")
        ).isInstanceOf(BusinessException.class)
                .hasMessageContaining("8 到 24 个字符");
    }

    @Test
    void changePassword_valid_savesNewHash() {
        UUID userId = UUID.randomUUID();
        AuthUser user = new AuthUser();
        user.setPasswordHash("$2a$10$oldHash");
        when(authUserRepository.findById(userId)).thenReturn(Optional.of(user));
        when(passwordEncoder.matches("oldPass", "$2a$10$oldHash")).thenReturn(true);
        when(passwordEncoder.encode("newPass123")).thenReturn("$2a$10$newHash");
        when(authUserRepository.save(any(AuthUser.class))).thenAnswer(i -> i.getArgument(0));

        service.changePassword(userId, "oldPass", "newPass123");

        verify(authUserRepository).save(user);
        assertThat(user.getPasswordHash()).isEqualTo("$2a$10$newHash");
    }

    private static ObjectStorageBuckets createObjectStorageBuckets() {
        ObjectStorageBuckets buckets = mock(ObjectStorageBuckets.class);
        when(buckets.derivedAssets()).thenReturn("derived-assets");
        return buckets;
    }

    private AuthRole role(String code, String permissionCode) {
        AuthPermission permission = new AuthPermission();
        permission.setId(UUID.randomUUID());
        permission.setCode(permissionCode);
        permission.setName(permissionCode);
        permission.setModule("system");

        AuthRole role = new AuthRole();
        role.setId(UUID.randomUUID());
        role.setCode(code);
        role.setName(code);
        role.getPermissions().add(permission);
        return role;
    }
}
