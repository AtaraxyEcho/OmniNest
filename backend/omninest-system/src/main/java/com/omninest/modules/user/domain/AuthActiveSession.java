package com.omninest.modules.user.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

/**
 * 活跃会话实体，用于登录互斥和会话管理。
 */
@Entity
@Table(name = "auth_active_sessions", schema = "omni")
@Getter
@Setter
@AllArgsConstructor
@NoArgsConstructor
public class AuthActiveSession {

    @Id
    private UUID id;

    @Column(name = "user_id", nullable = false)
    private UUID userId;

    @Column(name = "client_platform", nullable = false, length = 32)
    private String clientPlatform;

    @Column(name = "device_id", length = 128)
    private String deviceId;

    @Column(name = "device_name")
    private String deviceName;

    @Column(name = "ip_address", length = 45)
    private String ipAddress;

    @Column(name = "issued_at", nullable = false)
    private Instant issuedAt;

    @Column(name = "expires_at", nullable = false)
    private Instant expiresAt;

    @Column(name = "last_active_at", nullable = false)
    private Instant lastActiveAt;

    @Column(name = "revoked_at")
    private Instant revokedAt;

    @Column(name = "revoke_reason")
    private String revokeReason;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @PrePersist
    void fillDefaults() {
        if (id == null) {
            id = UUID.randomUUID();
        }
        Instant now = Instant.now();
        if (createdAt == null) {
            createdAt = now;
        }
        if (lastActiveAt == null) {
            lastActiveAt = now;
        }
    }

    /**
     * 判断会话是否已撤销。
     */
    public boolean isRevoked() {
        return revokedAt != null;
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (!(o instanceof AuthActiveSession other)) return false;
        return id != null && id.equals(other.getId());
    }

    @Override
    public int hashCode() {
        return getClass().hashCode();
    }

    /**
     * 仅输出标识与客户端平台，避免设备和网络信息进入日志。
     */
    @Override
    public String toString() {
        return "AuthActiveSession{id=" + id + ", userId=" + userId
                + ", clientPlatform=" + clientPlatform + "}";
    }
}
