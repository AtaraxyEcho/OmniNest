package com.omninest.modules.user.service;

import com.omninest.common.config.BaseRuntimeConfigService;
import com.omninest.common.config.ConfigValueProvider;
import com.omninest.common.config.RuntimeConfigCache;
import com.omninest.common.security.Roles;
import com.omninest.modules.user.domain.AuthRole;
import com.omninest.modules.user.domain.AuthUser;
import java.util.Locale;
import java.util.Set;
import java.util.stream.Collectors;
import org.springframework.stereotype.Service;

/**
 * 两步验证强制策略，从配置中心读取必须开启两步验证的角色编码列表。
 *
 * <p>键为 {@code auth.two-factor.required-roles}，逗号分隔；默认超管与管理员强制，
 * 解析失败或留空时回落全员自愿（空集合）。</p>
 *
 * @author OmniNest
 */
@Service
public class TwoFactorPolicyService extends BaseRuntimeConfigService {

    public static final String REQUIRED_ROLES_KEY = "auth.two-factor.required-roles";
    static final String DEFAULT_REQUIRED_ROLES = Roles.SUPER_ADMIN + "," + Roles.ADMIN;

    /**
     * 创建两步验证策略服务。
     *
     * @param configValueProvider 配置值查询端口
     * @param runtimeConfigCache 运行时配置缓存端口
     */
    public TwoFactorPolicyService(
            ConfigValueProvider configValueProvider,
            RuntimeConfigCache runtimeConfigCache
    ) {
        super(configValueProvider, runtimeConfigCache);
    }

    /**
     * 判断用户是否属于强制开启两步验证的角色。
     *
     * @param user 已加载角色的用户
     * @return 是否强制
     */
    public boolean isRequired(AuthUser user) {
        if (user == null || user.getRoles() == null || user.getRoles().isEmpty()) {
            return false;
        }
        Set<String> requiredRoles = requiredRoles();
        if (requiredRoles.isEmpty()) {
            return false;
        }
        return user.getRoles().stream()
                .map(AuthRole::getCode)
                .filter(code -> code != null && !code.isBlank())
                .map(code -> code.trim().toUpperCase(Locale.ROOT))
                .anyMatch(requiredRoles::contains);
    }

    /**
     * 解析强制角色集合：配置缺失用默认值，显式留空表示全员自愿。
     *
     * @return 强制角色编码集合
     */
    public Set<String> requiredRoles() {
        String raw = cachedConfigValue(REQUIRED_ROLES_KEY).orElse(DEFAULT_REQUIRED_ROLES);
        if (raw == null || raw.isBlank()) {
            return Set.of();
        }
        return java.util.Arrays.stream(raw.split(","))
                .map(String::trim)
                .filter(code -> !code.isBlank())
                .map(code -> code.toUpperCase(Locale.ROOT))
                .collect(Collectors.toUnmodifiableSet());
    }
}
