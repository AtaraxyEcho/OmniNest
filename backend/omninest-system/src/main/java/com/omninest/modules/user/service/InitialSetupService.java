package com.omninest.modules.user.service;

import com.omninest.common.config.RuntimeConfigCache;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.security.Roles;
import com.omninest.modules.configcenter.repository.ConfigEntryRepository;
import com.omninest.modules.configcenter.domain.ConfigEntry;
import com.omninest.modules.user.config.InitialSetupProperties;
import com.omninest.modules.user.domain.AuthRole;
import com.omninest.modules.user.domain.AuthUser;
import com.omninest.modules.user.domain.SystemInstance;
import com.omninest.modules.user.domain.SystemInstanceState;
import com.omninest.modules.user.domain.UserStatus;
import com.omninest.modules.user.dto.InitialSetupRequest;
import com.omninest.modules.user.dto.InitialSetupStatusDto;
import com.omninest.modules.user.dto.TwoFactorDtos.TwoFactorSetupResponse;
import com.omninest.modules.user.repository.AuthRoleRepository;
import com.omninest.modules.user.repository.AuthUserRepository;
import com.omninest.modules.user.repository.SystemInstanceRepository;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.DateTimeException;
import java.time.ZoneId;
import java.util.List;
import java.util.Locale;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 管理首次安装状态并以一次性流程创建超级管理员。
 *
 * <p>安装向导可按部署形态要求同步完成两步验证注册（omninest.setup.two-factor-required，
 * 环境变量 OMNINEST_SETUP_TWOFACTORREQUIRED），完成时把结果播种进配置中心，
 * 使运行期强制策略与部署姿态一致。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class InitialSetupService {
    private static final String DEFAULT_INSTANCE_NAME = "OmniNest";
    private static final String DEFAULT_LOCALE = "zh-CN";
    private static final String DEFAULT_TIMEZONE = "Asia/Shanghai";
    private static final int MIN_SETUP_TOKEN_LENGTH = 32;
    private final InitialSetupProperties properties;
    private final AuthUserRepository authUserRepository;
    private final AuthRoleRepository authRoleRepository;
    private final SystemInstanceRepository systemInstanceRepository;
    private final PasswordEncoder passwordEncoder;
    private final PasswordPolicy passwordPolicy;
    private final TwoFactorService twoFactorService;
    private final ConfigEntryRepository configEntryRepository;
    private final RuntimeConfigCache runtimeConfigCache;

    /**
     * 查询首次安装向导状态。
     *
     * @return 不包含安装令牌内容的状态
     */
    @Transactional(readOnly = true)
    public InitialSetupStatusDto status() {
        boolean persistentStateEnabled = properties.isPersistentStateEnabled();
        boolean setupRequired = persistentStateEnabled
                ? requireSystemInstance().getSetupState() == SystemInstanceState.SETUP_REQUIRED
                : !authUserRepository.existsByRoles_Code(Roles.SUPER_ADMIN);
        return new InitialSetupStatusDto(
                setupRequired,
                setupRequired && hasValidConfiguredToken(),
                persistentStateEnabled,
                setupRequired && properties.isTwoFactorRequired()
        );
    }

    /**
     * 安装向导生成两步验证秘钥；仅在安装未完成时可用。
     *
     * @param username 向导中输入的超管用户名
     * @return 秘钥与 otpauth URI
     */
    @Transactional(readOnly = true)
    public TwoFactorSetupResponse newTwoFactorSecret(String username) {
        requireSetupStillRequired();
        return twoFactorService.newSetupSecret(username);
    }

    /**
     * 校验安装令牌并创建首个超级管理员，按部署姿态同步完成两步验证注册并播种运行期策略。
     *
     * @param setupToken 客户端提交的安装令牌
     * @param request 超级管理员资料
     * @return 启用两步验证时的一次性备份码，未启用时为 null
     */
    @Transactional(rollbackFor = Exception.class)
    public List<String> createSuperAdmin(String setupToken, InitialSetupRequest request) {
        requireValidSetupToken(setupToken);
        SystemInstance systemInstance = lockSystemInstance();
        if (properties.isPersistentStateEnabled()
                && systemInstance.getSetupState() == SystemInstanceState.READY) {
            throw new BusinessException(ErrorCode.CONFLICT, "首次安装已经完成");
        }
        AuthRole superAdminRole = authRoleRepository.findByCodeForUpdate(Roles.SUPER_ADMIN)
                .orElseThrow(() -> new BusinessException(
                        ErrorCode.DEPENDENCY_UNAVAILABLE,
                        "超级管理员角色尚未初始化"
                ));
        if (authUserRepository.existsByRoles_Code(Roles.SUPER_ADMIN)) {
            throw new BusinessException(ErrorCode.CONFLICT, "首次安装已经完成");
        }
        String username = request.username().trim();
        if (authUserRepository.existsByUsername(username)) {
            throw new BusinessException(ErrorCode.CONFLICT, "用户名已存在");
        }
        passwordPolicy.validate(username, request.password());
        List<String> backupCodes = null;
        if (properties.isTwoFactorRequired()) {
            if (request.totpSecret() == null || request.totpSecret().isBlank()
                    || request.totpCode() == null || request.totpCode().isBlank()) {
                throw new BusinessException(ErrorCode.BAD_REQUEST, "安装向导要求完成两步验证注册");
            }
        }

        AuthUser user = new AuthUser();
        user.setUsername(username);
        user.setPasswordHash(passwordEncoder.encode(request.password()));
        user.setDisplayName(normalizeDisplayName(request.displayName(), username));
        user.setEmail(normalizeEmail(request.email()));
        user.setStatus(UserStatus.ACTIVE.getValue());
        user.getRoles().add(superAdminRole);
        AuthUser savedUser = authUserRepository.saveAndFlush(user);
        if (properties.isTwoFactorRequired()) {
            backupCodes = twoFactorService.provisionForNewUser(
                    savedUser.getId(),
                    request.totpSecret(),
                    request.totpCode()
            );
        }
        systemInstance.complete(
                savedUser.getId(),
                normalizeInstanceName(request.instanceName()),
                normalizeLocale(request.defaultLocale()),
                normalizeTimezone(request.defaultTimezone())
        );
        systemInstanceRepository.save(systemInstance);
        seedTwoFactorRuntimePolicy(properties.isTwoFactorRequired());
        log.info("首次安装已创建超级管理员: username={}, twoFactor={}", username, properties.isTwoFactorRequired());
        return backupCodes;
    }

    /**
     * 把安装期的两步验证姿态写入配置中心，使运行期强制策略与部署选择一致；
     * 直写行并逐出缓存（安装期无认证上下文，不走 ConfigCenterService 的权限路径）。
     */
    private void seedTwoFactorRuntimePolicy(boolean required) {
        String value = required ? TwoFactorPolicyService.DEFAULT_REQUIRED_ROLES : "";
        configEntryRepository.findByConfigKey(TwoFactorPolicyService.REQUIRED_ROLES_KEY)
                .ifPresent(entry -> {
                    entry.setConfigValue(value);
                    configEntryRepository.save(entry);
                });
        runtimeConfigCache.evict(TwoFactorPolicyService.REQUIRED_ROLES_KEY);
    }

    private void requireSetupStillRequired() {
        boolean setupRequired = properties.isPersistentStateEnabled()
                ? requireSystemInstance().getSetupState() == SystemInstanceState.SETUP_REQUIRED
                : !authUserRepository.existsByRoles_Code(Roles.SUPER_ADMIN);
        if (!setupRequired) {
            throw new BusinessException(ErrorCode.CONFLICT, "首次安装已经完成");
        }
    }

    private SystemInstance lockSystemInstance() {
        return systemInstanceRepository.findByIdForUpdate(SystemInstance.SINGLETON_ID)
                .orElseGet(() -> {
                    if (properties.isPersistentStateEnabled()) {
                        throw new BusinessException(
                                ErrorCode.DEPENDENCY_UNAVAILABLE,
                                "系统实例状态尚未初始化"
                        );
                    }
                    return newTransientSystemInstance();
                });
    }

    private SystemInstance requireSystemInstance() {
        return systemInstanceRepository.findById(SystemInstance.SINGLETON_ID)
                .orElseThrow(() -> new BusinessException(
                        ErrorCode.DEPENDENCY_UNAVAILABLE,
                        "系统实例状态尚未初始化"
                ));
    }

    private SystemInstance newTransientSystemInstance() {
        SystemInstance systemInstance = new SystemInstance();
        systemInstance.setId(SystemInstance.SINGLETON_ID);
        return systemInstance;
    }

    private void requireValidSetupToken(String providedToken) {
        String configuredToken = properties.getToken();
        if (!properties.isEnabled()
                || configuredToken == null
                || configuredToken.length() < MIN_SETUP_TOKEN_LENGTH
                || providedToken == null
                || !MessageDigest.isEqual(
                        configuredToken.getBytes(StandardCharsets.UTF_8),
                        providedToken.getBytes(StandardCharsets.UTF_8)
                )) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "安装凭据无效或安装向导不可用");
        }
    }

    private boolean hasValidConfiguredToken() {
        String token = properties.getToken();
        return properties.isEnabled() && token != null && token.length() >= MIN_SETUP_TOKEN_LENGTH;
    }

    private String normalizeDisplayName(String rawDisplayName, String username) {
        String displayName = rawDisplayName == null ? "" : rawDisplayName.trim();
        return displayName.isEmpty() ? username : displayName;
    }

    private String normalizeEmail(String rawEmail) {
        String email = rawEmail == null ? "" : rawEmail.trim();
        return email.isEmpty() ? null : email;
    }

    private String normalizeInstanceName(String rawInstanceName) {
        String instanceName = rawInstanceName == null ? "" : rawInstanceName.trim();
        return instanceName.isEmpty() ? DEFAULT_INSTANCE_NAME : instanceName;
    }

    private String normalizeLocale(String rawLocale) {
        String localeTag = rawLocale == null ? "" : rawLocale.trim();
        if (localeTag.isEmpty()) {
            return DEFAULT_LOCALE;
        }
        Locale locale = Locale.forLanguageTag(localeTag);
        if (locale.getLanguage().isEmpty() || "und".equals(locale.toLanguageTag())) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "默认语言格式不正确");
        }
        return locale.toLanguageTag();
    }

    private String normalizeTimezone(String rawTimezone) {
        String timezone = rawTimezone == null ? "" : rawTimezone.trim();
        if (timezone.isEmpty()) {
            return DEFAULT_TIMEZONE;
        }
        try {
            return ZoneId.of(timezone).getId();
        } catch (DateTimeException exception) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "默认时区格式不正确");
        }
    }

}
