package com.omninest.modules.user.service;

import com.omninest.common.security.Roles;
import com.omninest.modules.user.domain.AuthRole;
import com.omninest.modules.user.domain.AuthUser;
import com.omninest.modules.user.repository.AuthUserRepository;
import java.util.UUID;
import org.springframework.stereotype.Service;

/**
 * 两步验证强制策略：仅超级管理员必须完成注册，普通账户由用户自行选择。
 *
 * @author OmniNest
 */
@Service
public class TwoFactorPolicyService {

    public static final String REQUIRED_ROLES_KEY = "auth.two-factor.required-roles";
    static final String DEFAULT_REQUIRED_ROLES = Roles.SUPER_ADMIN;

    private final AuthUserRepository authUserRepository;

    /**
     * 创建两步验证策略服务。
     *
     * @param authUserRepository 用户查询端口
     */
    public TwoFactorPolicyService(AuthUserRepository authUserRepository) {
        this.authUserRepository = authUserRepository;
    }

    /**
     * 按用户 ID 判断是否强制两步验证。
     *
     * @param userId 用户 ID
     * @return 是否强制
     */
    public boolean isRequired(UUID userId) {
        return authUserRepository.findWithRolesById(userId)
                .map(this::isRequired)
                .orElse(false);
    }

    public boolean isRequired(AuthUser user) {
        if (user == null) {
            return false;
        }
        if (user.getRoles() == null || user.getRoles().isEmpty()) {
            return false;
        }
        return user.getRoles().stream()
                .map(AuthRole::getCode)
                .filter(code -> code != null && !code.isBlank())
                .anyMatch(code -> Roles.SUPER_ADMIN.equalsIgnoreCase(code.trim()));
    }
}
