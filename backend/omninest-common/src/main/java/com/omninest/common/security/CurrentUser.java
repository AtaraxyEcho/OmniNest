package com.omninest.common.security;

import java.util.Set;
import java.util.UUID;

/**
 * 当前认证用户信息。
 *
 * @param userId 用户标识
 * @param subject JWT 主题
 * @param username 用户名
 * @param permissions 权限编码集合
 * @param roles 角色编码集合
 * @author OmniNest
 */
public record CurrentUser(
        UUID userId,
        String subject,
        String username,
        Set<String> permissions,
        Set<String> roles
) {
    /**
     * 判断当前用户是否具有管理员角色。
     *
     * <p>超级管理员不必然冗余绑定 ADMIN，只判 ADMIN 会把仅持 SUPER_ADMIN 的账户
     * 当成普通用户；授权仍以权限编码为准，本方法只用于粗粒度分支。</p>
     *
     * @return 具有管理员角色时返回 true
     */
    public boolean isAdmin() {
        return roles != null && (roles.contains(Roles.ADMIN) || roles.contains(Roles.SUPER_ADMIN));
    }
}
