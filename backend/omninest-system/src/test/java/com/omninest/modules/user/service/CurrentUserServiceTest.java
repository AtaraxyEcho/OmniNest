package com.omninest.modules.user.service;

import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.net.URI;
import java.util.function.Supplier;
import javax.imageio.ImageIO;
import org.mockito.ArgumentCaptor;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.when;
import static org.mockito.Mockito.inOrder;

import com.omninest.common.cache.ReadThroughCache;
import com.omninest.common.security.CurrentUserContext;
import com.omninest.common.security.MalwareScanGateway;
import com.omninest.common.security.Permissions;
import com.omninest.common.security.Roles;
import com.omninest.common.storage.ObjectStorageBuckets;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.common.error.BusinessException;
import com.omninest.common.sync.UserSyncEventRecorder;
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
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.InOrder;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionStatus;
import org.springframework.web.multipart.MultipartFile;
import com.omninest.common.storage.ObjectStorageKey;
import com.omninest.modules.user.util.UserAvatarObjectKeys;
import java.net.URI;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
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
    private final UserSessionRevocationService userSessionRevocationService = mock(UserSessionRevocationService.class);
    private final ReadThroughCache readThroughCache = mock(ReadThroughCache.class, invocation -> {
        if ("getOrLoad".equals(invocation.getMethod().getName())) {
            Supplier<?> loader = invocation.getArgument(2);
            return loader.get();
        }
        return null;
    });
    private final MalwareScanGateway malwareScanGateway = mock(MalwareScanGateway.class);
    private final UserSyncEventRecorder syncEventRecorder = mock(UserSyncEventRecorder.class);
    private final PlatformTransactionManager transactionManager = mock(PlatformTransactionManager.class);
    private final CurrentUserService service = new CurrentUserService(
            authUserRepository, activeSessionRepository, currentUserContext, passwordEncoder,
            new PasswordPolicy(), objectStorageClient, objectStorageBuckets, notificationService, sessionRevocationService,
            userSessionRevocationService, readThroughCache, malwareScanGateway, syncEventRecorder,
            transactionManager);

    @BeforeEach
    void setUpTransactionTemplate() {
        service.initTransactionTemplate();
        when(transactionManager.getTransaction(any())).thenReturn(mock(TransactionStatus.class));
    }

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
        when(authUserRepository.findWithRolesAndPermissionsById(userId)).thenReturn(Optional.of(existing));

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
        when(authUserRepository.findWithRolesAndPermissionsById(userId)).thenReturn(Optional.of(existing));

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
        when(authUserRepository.findWithRolesAndPermissionsById(userId)).thenReturn(Optional.empty());

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
        verify(userSessionRevocationService).revokeAllExcept(
                userId, null, "PASSWORD_CHANGED");
    }

    @Test
    void changePassword_revokesOtherSessionsKeepingCurrentOne() {
        UUID userId = UUID.randomUUID();
        UUID currentSessionId = UUID.randomUUID();
        AuthUser user = new AuthUser();
        user.setPasswordHash("$2a$10$oldHash");
        when(authUserRepository.findById(userId)).thenReturn(Optional.of(user));
        when(passwordEncoder.matches("oldPass", "$2a$10$oldHash")).thenReturn(true);
        when(passwordEncoder.encode("newPass123")).thenReturn("$2a$10$newHash");
        when(authUserRepository.save(any(AuthUser.class))).thenAnswer(i -> i.getArgument(0));
        when(currentUserContext.currentSessionId()).thenReturn(currentSessionId);

        service.changePassword(userId, "oldPass", "newPass123");

        verify(userSessionRevocationService).revokeAllExcept(
                userId, currentSessionId, "PASSWORD_CHANGED");
    }

    @Test
    void updateProfile_updatesProvidedFieldsAndInvalidatesCache() {
        UUID userId = UUID.randomUUID();
        AuthUser user = new AuthUser();
        user.setId(userId);
        user.setUsername("root");
        user.setDisplayName("Root");
        user.setEmail("root@example.com");
        when(authUserRepository.findById(userId)).thenReturn(Optional.of(user));
        when(authUserRepository.save(any(AuthUser.class))).thenAnswer(i -> i.getArgument(0));
        when(authUserRepository.findWithRolesAndPermissionsById(userId)).thenReturn(Optional.of(user));

        service.updateProfile(userId, "  New Name  ", null);

        assertThat(user.getDisplayName()).isEqualTo("New Name");
        assertThat(user.getEmail()).isEqualTo("root@example.com");
        verify(readThroughCache).invalidate("omninest:user:profile:" + userId);
        verify(syncEventRecorder).record(any());
    }

    @Test
    void updateProfile_noChanges_returnsCachedWithoutSave() {
        UUID userId = UUID.randomUUID();
        AuthUser user = new AuthUser();
        user.setId(userId);
        user.setUsername("root");
        user.setDisplayName("Root");
        user.setEmail("root@example.com");
        user.getRoles().add(role("ADMIN", Permissions.SYSTEM_CONFIG_MANAGE));
        when(currentUserContext.requireCurrentUserId()).thenReturn(userId);
        when(authUserRepository.findById(userId)).thenReturn(Optional.of(user));
        when(authUserRepository.findWithRolesAndPermissionsById(userId)).thenReturn(Optional.of(user));

        var profile = service.updateProfile(userId, "Root", "root@example.com");

        assertThat(profile.displayName()).isEqualTo("Root");
        verify(authUserRepository, never()).save(any(AuthUser.class));
    }

    @Test
    void updateProfile_invalidDisplayName_throws() {
        UUID userId = UUID.randomUUID();
        AuthUser user = new AuthUser();
        when(authUserRepository.findById(userId)).thenReturn(Optional.of(user));

        assertThatThrownBy(() -> service.updateProfile(userId, "   ", null))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("显示昵称");
    }

    @Test
    void updateProfile_invalidEmail_throws() {
        UUID userId = UUID.randomUUID();
        AuthUser user = new AuthUser();
        when(authUserRepository.findById(userId)).thenReturn(Optional.of(user));

        assertThatThrownBy(() -> service.updateProfile(userId, null, "not-an-email"))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("邮箱");
    }

    @Test
    void updateProfile_emptyEmail_clearsEmail() {
        UUID userId = UUID.randomUUID();
        AuthUser user = new AuthUser();
        user.setId(userId);
        user.setEmail("root@example.com");
        when(authUserRepository.findById(userId)).thenReturn(Optional.of(user));
        when(authUserRepository.save(any(AuthUser.class))).thenAnswer(i -> i.getArgument(0));
        when(authUserRepository.findWithRolesAndPermissionsById(userId)).thenReturn(Optional.of(user));

        service.updateProfile(userId, null, "  ");

        assertThat(user.getEmail()).isNull();
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

    @Test
    void uploadAvatarStoresObjectUnderAvatarFileIdKeyInsideShortTransaction() throws IOException {
        UUID userId = UUID.fromString("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");
        AuthUser existing = new AuthUser();
        existing.setId(userId);
        existing.setUsername("root");
        byte[] png = pngBytes();
        when(malwareScanGateway.scan(any(), anyLong()))
                .thenReturn(new MalwareScanGateway.ScanResult(MalwareScanGateway.Status.CLEAN, null));
        when(authUserRepository.findById(userId)).thenReturn(Optional.of(existing));
        when(authUserRepository.save(any())).thenAnswer(invocation -> invocation.getArgument(0));
        when(objectStorageClient.createDownloadUrl(any(), any()))
                .thenReturn(URI.create("https://minio/signed-avatar"));

        String url = service.uploadAvatar(userId, multipartPng(png));

        assertThat(url).isEqualTo("https://minio/signed-avatar");
        UUID avatarFileId = existing.getAvatarFileId();
        assertThat(avatarFileId).isNotNull();
        // 对象键由头像标识决定：读取侧无需按扩展名探测，旧格式头像也不可能再遮蔽新头像。
        ArgumentCaptor<ObjectStorageKey> keyCaptor = ArgumentCaptor.forClass(ObjectStorageKey.class);
        verify(objectStorageClient).putObject(keyCaptor.capture(), any(), anyLong(), eq("image/png"));
        assertThat(keyCaptor.getValue().objectKey())
                .isEqualTo(UserAvatarObjectKeys.objectKey(userId, avatarFileId));
        // 落库与同步事件必须落在同一事务边界内（同步事件记录器是 MANDATORY 传播）。
        InOrder order = inOrder(transactionManager, authUserRepository, syncEventRecorder);
        order.verify(transactionManager).getTransaction(any());
        order.verify(authUserRepository).save(existing);
        order.verify(syncEventRecorder).record(any());
        order.verify(transactionManager).commit(any());
    }

    private static MultipartFile multipartPng(byte[] content) throws IOException {
        MultipartFile file = mock(MultipartFile.class);
        when(file.isEmpty()).thenReturn(false);
        when(file.getSize()).thenReturn((long) content.length);
        when(file.getInputStream()).thenReturn(new ByteArrayInputStream(content));
        return file;
    }

    private static byte[] pngBytes() throws IOException {
        BufferedImage image = new BufferedImage(8, 8, BufferedImage.TYPE_INT_RGB);
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        ImageIO.write(image, "png", out);
        return out.toByteArray();
    }
}
