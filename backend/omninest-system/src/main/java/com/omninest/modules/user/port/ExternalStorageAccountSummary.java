package com.omninest.modules.user.port;

import java.time.Instant;
import java.util.UUID;

/**
 * 外部存储账户摘要。
 *
 * @param id 账户标识
 * @param ownerUserId 所属用户标识，供管理端监管展示
 * @param provider 存储提供方
 * @param displayName 显示名称
 * @param status 账户状态
 * @param createdAt 创建时间
 * @param updatedAt 更新时间
 * @author OmniNest
 */
public record ExternalStorageAccountSummary(
        UUID id,
        UUID ownerUserId,
        String provider,
        String displayName,
        String status,
        Instant createdAt,
        Instant updatedAt
) {
}
