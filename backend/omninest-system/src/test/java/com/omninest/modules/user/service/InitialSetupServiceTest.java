package com.omninest.modules.user.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.eq;
import static org.mockito.Mockito.isNull;

import com.omninest.common.config.RuntimeConfigCache;
import com.omninest.common.error.BusinessException;
import com.omninest.common.security.Roles;
import com.omninest.modules.configcenter.domain.ConfigEntry;
import com.omninest.modules.configcenter.repository.ConfigEntryRepository;
import com.omninest.modules.user.config.InitialSetupProperties;
import com.omninest.modules.user.domain.AuthRole;
import com.omninest.modules.user.domain.AuthUser;
import com.omninest.modules.user.domain.SystemInstance;
import com.omninest.modules.user.domain.SystemInstanceState;
import com.omninest.modules.user.dto.InitialSetupRequest;
import com.omninest.modules.user.repository.AuthRoleRepository;
import com.omninest.modules.user.repository.AuthUserRepository;
import com.omninest.modules.user.repository.SystemInstanceRepository;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.Mockito;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;

/**
 * 首次安装服务测试。
 *
 * @author OmniNest
 */
class InitialSetupServiceTest {
    private static final String SETUP_TOKEN = "0123456789abcdef0123456789abcdef";

    private final InitialSetupProperties properties = new InitialSetupProperties();
    private final AuthUserRepository authUserRepository = Mockito.mock(AuthUserRepository.class);
    private final AuthRoleRepository authRoleRepository = Mockito.mock(AuthRoleRepository.class);
    private final SystemInstanceRepository systemInstanceRepository = Mockito.mock(SystemInstanceRepository.class);
    private final PasswordEncoder passwordEncoder = new BCryptPasswordEncoder();
    private final TwoFactorService twoFactorService = Mockito.mock(TwoFactorService.class);
    private final ConfigEntryRepository configEntryRepository = Mockito.mock(ConfigEntryRepository.class);
    private final RuntimeConfigCache runtimeConfigCache = Mockito.mock(RuntimeConfigCache.class);
    private final InitialSetupService service = new InitialSetupService(
            properties,
            authUserRepository,
            authRoleRepository,
            systemInstanceRepository,
            passwordEncoder,
            new PasswordPolicy(),
            twoFactorService,
            configEntryRepository,
            runtimeConfigCache
    );

    @BeforeEach
    void setUp() {
        properties.setEnabled(true);
        properties.setToken(SETUP_TOKEN);
        properties.setPersistentStateEnabled(true);
        properties.setTwoFactorRequired(false);
        Mockito.when(configEntryRepository.findByConfigKey(TwoFactorPolicyService.REQUIRED_ROLES_KEY))
                .thenReturn(Optional.of(Mockito.mock(ConfigEntry.class)));
    }

    @Test
    void reportsAvailableWhenSuperAdminIsMissingAndTokenIsConfigured() {
        Mockito.when(systemInstanceRepository.findById(SystemInstance.SINGLETON_ID))
                .thenReturn(Optional.of(requiredInstance()));

        var status = service.status();

        assertThat(status.setupRequired()).isTrue();
        assertThat(status.setupAvailable()).isTrue();
        assertThat(status.persistentStateEnabled()).isTrue();
    }

    @Test
    void reportsCompletedWhenSuperAdminExists() {
        SystemInstance systemInstance = requiredInstance();
        systemInstance.setSetupState(SystemInstanceState.READY);
        Mockito.when(systemInstanceRepository.findById(SystemInstance.SINGLETON_ID))
                .thenReturn(Optional.of(systemInstance));

        var status = service.status();

        assertThat(status.setupRequired()).isFalse();
        assertThat(status.setupAvailable()).isFalse();
    }

    @Test
    void derivesStatusFromSuperAdminWhenPersistentStateIsDisabled() {
        properties.setPersistentStateEnabled(false);
        Mockito.when(authUserRepository.existsByRoles_Code(Roles.SUPER_ADMIN)).thenReturn(false);

        var status = service.status();

        assertThat(status.setupRequired()).isTrue();
        assertThat(status.persistentStateEnabled()).isFalse();
        Mockito.verify(systemInstanceRepository, Mockito.never()).findById(Mockito.any());
    }

    @Test
    void createsSuperAdminAfterLockingRole() {
        SystemInstance systemInstance = requiredInstance();
        AuthRole role = new AuthRole();
        role.setId(UUID.randomUUID());
        role.setCode(Roles.SUPER_ADMIN);
        Mockito.when(systemInstanceRepository.findByIdForUpdate(SystemInstance.SINGLETON_ID))
                .thenReturn(Optional.of(systemInstance));
        Mockito.when(authRoleRepository.findByCodeForUpdate(Roles.SUPER_ADMIN)).thenReturn(Optional.of(role));
        Mockito.when(authUserRepository.existsByRoles_Code(Roles.SUPER_ADMIN)).thenReturn(false);
        Mockito.when(authUserRepository.existsByUsername("root")).thenReturn(false);
        Mockito.when(authUserRepository.saveAndFlush(Mockito.any())).thenAnswer(invocation -> {
            AuthUser user = invocation.getArgument(0);
            user.setId(UUID.randomUUID());
            return user;
        });

        service.createSuperAdmin(
                SETUP_TOKEN,
                new InitialSetupRequest(
                        " root ",
                        " 管理员 ",
                        " root@example.com ",
                        "ChangeMe123!",
                        " 家庭中心 ",
                        "zh-cn",
                        "Asia/Shanghai",
                        null,
                        null
                )
        );

        ArgumentCaptor<AuthUser> captor = ArgumentCaptor.forClass(AuthUser.class);
        Mockito.verify(authUserRepository).saveAndFlush(captor.capture());
        AuthUser user = captor.getValue();
        assertThat(user.getUsername()).isEqualTo("root");
        assertThat(user.getDisplayName()).isEqualTo("管理员");
        assertThat(user.getEmail()).isEqualTo("root@example.com");
        assertThat(user.getRoles()).containsExactly(role);
        assertThat(passwordEncoder.matches("ChangeMe123!", user.getPasswordHash())).isTrue();
        assertThat(systemInstance.getSetupState()).isEqualTo(SystemInstanceState.READY);
        assertThat(systemInstance.getInstanceName()).isEqualTo("家庭中心");
        assertThat(systemInstance.getDefaultLocale()).isEqualTo("zh-CN");
        Mockito.verify(systemInstanceRepository).save(systemInstance);
    }

    @Test
    void rejectsInvalidTokenBeforeDatabaseLock() {
        assertThatThrownBy(() -> service.createSuperAdmin(
                "wrong-token",
                request("ChangeMe123!")
        )).isInstanceOf(BusinessException.class)
                .hasMessageContaining("安装凭据无效");

        Mockito.verify(authRoleRepository, Mockito.never()).findByCodeForUpdate(Mockito.any());
        Mockito.verify(systemInstanceRepository, Mockito.never()).findByIdForUpdate(Mockito.any());
        Mockito.verify(authUserRepository, Mockito.never()).saveAndFlush(Mockito.any());
    }

    @Test
    void rejectsSecondSetupAfterRoleLock() {
        SystemInstance systemInstance = requiredInstance();
        AuthRole role = new AuthRole();
        role.setCode(Roles.SUPER_ADMIN);
        Mockito.when(systemInstanceRepository.findByIdForUpdate(SystemInstance.SINGLETON_ID))
                .thenReturn(Optional.of(systemInstance));
        Mockito.when(authRoleRepository.findByCodeForUpdate(Roles.SUPER_ADMIN)).thenReturn(Optional.of(role));
        Mockito.when(authUserRepository.existsByRoles_Code(Roles.SUPER_ADMIN)).thenReturn(true);

        assertThatThrownBy(() -> service.createSuperAdmin(
                SETUP_TOKEN,
                request("ChangeMe123!")
        )).isInstanceOf(BusinessException.class)
                .hasMessageContaining("已经完成");

        Mockito.verify(authUserRepository, Mockito.never()).saveAndFlush(Mockito.any());
    }

    @Test
    void rejectsWeakSuperAdminPassword() {
        Mockito.when(systemInstanceRepository.findByIdForUpdate(SystemInstance.SINGLETON_ID))
                .thenReturn(Optional.of(requiredInstance()));
        AuthRole role = new AuthRole();
        role.setCode(Roles.SUPER_ADMIN);
        Mockito.when(authRoleRepository.findByCodeForUpdate(Roles.SUPER_ADMIN)).thenReturn(Optional.of(role));
        Mockito.when(authUserRepository.existsByRoles_Code(Roles.SUPER_ADMIN)).thenReturn(false);
        Mockito.when(authUserRepository.existsByUsername("root")).thenReturn(false);

        assertThatThrownBy(() -> service.createSuperAdmin(
                SETUP_TOKEN,
                request("password1234")
        )).isInstanceOf(BusinessException.class)
                .hasMessageContaining("弱口令");

        Mockito.verify(authUserRepository, Mockito.never()).saveAndFlush(Mockito.any());
    }

    @Test
    void rejectsPasswordShorterThanSetupPolicy() {
        Mockito.when(systemInstanceRepository.findByIdForUpdate(SystemInstance.SINGLETON_ID))
                .thenReturn(Optional.of(requiredInstance()));
        AuthRole role = new AuthRole();
        role.setCode(Roles.SUPER_ADMIN);
        Mockito.when(authRoleRepository.findByCodeForUpdate(Roles.SUPER_ADMIN)).thenReturn(Optional.of(role));
        Mockito.when(authUserRepository.existsByRoles_Code(Roles.SUPER_ADMIN)).thenReturn(false);
        Mockito.when(authUserRepository.existsByUsername("root")).thenReturn(false);

        assertThatThrownBy(() -> service.createSuperAdmin(
                SETUP_TOKEN,
                request("short")
        )).isInstanceOf(BusinessException.class)
                .hasMessageContaining("8 到 24 个字符");

        Mockito.verify(authUserRepository, Mockito.never()).saveAndFlush(Mockito.any());
    }

    @Test
    void createsSuperAdminWithTwoFactorAndSeedsDefaultPolicy() {
        properties.setTwoFactorRequired(true);
        SystemInstance systemInstance = requiredInstance();
        AuthRole role = superAdminRole();
        Mockito.when(systemInstanceRepository.findByIdForUpdate(SystemInstance.SINGLETON_ID))
                .thenReturn(Optional.of(systemInstance));
        Mockito.when(authRoleRepository.findByCodeForUpdate(Roles.SUPER_ADMIN)).thenReturn(Optional.of(role));
        Mockito.when(authUserRepository.existsByRoles_Code(Roles.SUPER_ADMIN)).thenReturn(false);
        Mockito.when(authUserRepository.existsByUsername("root")).thenReturn(false);
        UUID createdUserId = UUID.randomUUID();
        Mockito.when(authUserRepository.saveAndFlush(any())).thenAnswer(invocation -> {
            AuthUser user = invocation.getArgument(0);
            user.setId(createdUserId);
            return user;
        });
        Mockito.when(twoFactorService.provisionForNewUser(createdUserId, "SECRET32", "123456"))
                .thenReturn(List.of("ABCD-2345"));
        ConfigEntry entry = Mockito.mock(ConfigEntry.class);

        Mockito.when(configEntryRepository.findByConfigKey(TwoFactorPolicyService.REQUIRED_ROLES_KEY))
                .thenReturn(Optional.of(entry));

        var backupCodes = service.createSuperAdmin(
                SETUP_TOKEN,
                new InitialSetupRequest(
                        "root", null, null, "ChangeMe123!", null, null, null,
                        "SECRET32", "123456"
                )
        );

        assertThat(backupCodes).containsExactly("ABCD-2345");
        Mockito.verify(twoFactorService).provisionForNewUser(createdUserId, "SECRET32", "123456");
        Mockito.verify(entry).setConfigValue("SUPER_ADMIN,ADMIN");
        Mockito.verify(configEntryRepository).save(entry);
        Mockito.verify(runtimeConfigCache).evict(TwoFactorPolicyService.REQUIRED_ROLES_KEY);
    }

    @Test
    void rejectsSetupWithoutTotpWhenTwoFactorRequired() {
        properties.setTwoFactorRequired(true);
        Mockito.when(systemInstanceRepository.findByIdForUpdate(SystemInstance.SINGLETON_ID))
                .thenReturn(Optional.of(requiredInstance()));
        Mockito.when(authRoleRepository.findByCodeForUpdate(Roles.SUPER_ADMIN))
                .thenReturn(Optional.of(superAdminRole()));
        Mockito.when(authUserRepository.existsByRoles_Code(Roles.SUPER_ADMIN)).thenReturn(false);
        Mockito.when(authUserRepository.existsByUsername("root")).thenReturn(false);

        assertThatThrownBy(() -> service.createSuperAdmin(
                SETUP_TOKEN,
                request("ChangeMe123!")
        )).isInstanceOf(BusinessException.class)
                .hasMessageContaining("安装向导要求完成两步验证注册");

        Mockito.verify(authUserRepository, Mockito.never()).saveAndFlush(any());
        Mockito.verify(twoFactorService, Mockito.never())
                .provisionForNewUser(any(), isNull(), isNull());
    }

    @Test
    void seedsVoluntaryPolicyWhenTwoFactorDisabled() {
        SystemInstance systemInstance = requiredInstance();
        Mockito.when(systemInstanceRepository.findByIdForUpdate(SystemInstance.SINGLETON_ID))
                .thenReturn(Optional.of(systemInstance));
        Mockito.when(authRoleRepository.findByCodeForUpdate(Roles.SUPER_ADMIN))
                .thenReturn(Optional.of(superAdminRole()));
        Mockito.when(authUserRepository.existsByRoles_Code(Roles.SUPER_ADMIN)).thenReturn(false);
        Mockito.when(authUserRepository.existsByUsername("root")).thenReturn(false);
        Mockito.when(authUserRepository.saveAndFlush(any())).thenAnswer(invocation -> {
            AuthUser user = invocation.getArgument(0);
            user.setId(UUID.randomUUID());
            return user;
        });
        ConfigEntry entry = Mockito.mock(ConfigEntry.class);
        Mockito.when(configEntryRepository.findByConfigKey(TwoFactorPolicyService.REQUIRED_ROLES_KEY))
                .thenReturn(Optional.of(entry));

        var backupCodes = service.createSuperAdmin(SETUP_TOKEN, request("ChangeMe123!"));

        assertThat(backupCodes).isNull();
        Mockito.verify(twoFactorService, Mockito.never()).provisionForNewUser(any(), any(), any());
        Mockito.verify(entry).setConfigValue("");
        Mockito.verify(runtimeConfigCache).evict(TwoFactorPolicyService.REQUIRED_ROLES_KEY);
    }

    @Test
    void statusReportsTwoFactorRequirement() {
        properties.setTwoFactorRequired(true);
        Mockito.when(systemInstanceRepository.findById(SystemInstance.SINGLETON_ID))
                .thenReturn(Optional.of(requiredInstance()));

        var status = service.status();

        assertThat(status.twoFactorRequired()).isTrue();
    }

    private AuthRole superAdminRole() {
        AuthRole role = new AuthRole();
        role.setId(UUID.randomUUID());
        role.setCode(Roles.SUPER_ADMIN);
        return role;
    }

    private InitialSetupRequest request(String password) {
        return new InitialSetupRequest(
                "root",
                null,
                null,
                password,
                null,
                null,
                null,
                null,
                null
        );
    }

    private SystemInstance requiredInstance() {
        SystemInstance systemInstance = new SystemInstance();
        systemInstance.setId(SystemInstance.SINGLETON_ID);
        systemInstance.setSetupState(SystemInstanceState.SETUP_REQUIRED);
        return systemInstance;
    }
}
