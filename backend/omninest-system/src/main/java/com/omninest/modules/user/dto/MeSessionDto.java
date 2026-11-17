package com.omninest.modules.user.dto;

import com.omninest.modules.user.domain.AuthActiveSession;
import java.time.Instant;
import java.util.UUID;

/**
 * 当前用户活跃会话展示 DTO。
 *
 * @param id 会话标识
 * @param clientPlatform 客户端平台（web/android 等）
 * @param deviceId 设备标识
 * @param deviceName 设备显示名
 * @param ipAddress 最近登录 IP
 * @param issuedAt 签发时间
 * @param expiresAt 截止时间
 * @param lastActiveAt 最后活跃时间
 * @param createdAt 创建时间
 * @param current 是否为发起本次请求的会话
 */
public record MeSessionDto(
        UUID id,
        String clientPlatform,
        String deviceId,
        String deviceName,
        String ipAddress,
        Instant issuedAt,
        Instant expiresAt,
        Instant lastActiveAt,
        Instant createdAt,
        boolean current
) {

    /**
     * 由会话实体构建展示 DTO，并按当前访问令牌会话标记 current。
     */
    public static MeSessionDto from(AuthActiveSession session, UUID currentSessionId) {
        return new MeSessionDto(
                session.getId(),
                session.getClientPlatform(),
                session.getDeviceId(),
                session.getDeviceName(),
                session.getIpAddress(),
                session.getIssuedAt(),
                session.getExpiresAt(),
                session.getLastActiveAt(),
                session.getCreatedAt(),
                currentSessionId != null && currentSessionId.equals(session.getId())
        );
    }
}
