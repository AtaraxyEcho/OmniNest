package com.omninest.common.user;

import java.util.Set;
import java.util.UUID;

/**
 * 跨模块使用的不可变用户账户摘要。
 *
 * @param id 用户 ID
 * @param username 用户名
 * @param roleIds 角色 ID 集合
 * @param superAdmin 是否为超级管理员
 * @param quotaBytes 存储配额字节数
 * @param usedBytes 已使用字节数
 * @author OmniNest
 */
public record UserAccountSummary(
        UUID id,
        String username,
        Set<UUID> roleIds,
        boolean superAdmin,
        long quotaBytes,
        long usedBytes,
        long reservedBytes
) {

    /**
     * 兼容既有调用方的六参数构造：未提供在途预留时按 0 处理。
     */
    public UserAccountSummary(
            UUID id,
            String username,
            Set<UUID> roleIds,
            boolean superAdmin,
            long quotaBytes,
            long usedBytes
    ) {
        this(id, username, roleIds, superAdmin, quotaBytes, usedBytes, 0L);
    }

    /**
     * 复制角色集合，防止调用方修改摘要内容。
     */
    public UserAccountSummary {
        roleIds = roleIds == null ? Set.of() : Set.copyOf(roleIds);
    }
}
