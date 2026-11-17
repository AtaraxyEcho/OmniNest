package com.omninest.modules.integration.service;

import java.time.Instant;
import java.util.Map;
import java.util.UUID;

/**
 * 外部集成账号的内部服务数据。
 *
 * @param id 账号 ID
 * @param ownerUserId 所属用户 ID
 * @param integrationType 集成类型
 * @param provider 提供者
 * @param externalUserId 外部用户 ID
 * @param displayName 显示名称
 * @param avatarUrl 头像地址
 * @param credentials 已解密凭据
 * @param status 状态
 * @param lastVerifiedAt 最近验证时间
 * @author OmniNest
 */
public record IntegrationAccountData(
        UUID id,
        UUID ownerUserId,
        String integrationType,
        String provider,
        String externalUserId,
        String displayName,
        String avatarUrl,
        Map<String, String> credentials,
        String status,
        Instant lastVerifiedAt
) {
}
