package com.omninest.common.user;

import java.util.Set;
import java.util.UUID;

/**
 * 跨模块使用的不可变用户账户详情。
 *
 * @param id 用户标识
 * @param username 用户名
 * @param displayName 展示名称
 * @param avatarUrl 头像地址
 * @param email 邮箱
 * @param status 账户状态
 * @param role 主要角色
 * @param roles 角色编码集合
 * @param permissions 权限编码集合
 * @param quotaBytes 存储配额字节数
 * @param usedBytes 已使用字节数
 * @author OmniNest
 */
public record UserAccountDetails(
        UUID id,
        String username,
        String displayName,
        String avatarUrl,
        String email,
        String status,
        String role,
        Set<String> roles,
        Set<String> permissions,
        long quotaBytes,
        long usedBytes
) {

    /**
     * 复制角色和权限集合，防止调用方修改详情内容。
     */
    public UserAccountDetails {
        roles = roles == null ? Set.of() : Set.copyOf(roles);
        permissions = permissions == null ? Set.of() : Set.copyOf(permissions);
    }
}
