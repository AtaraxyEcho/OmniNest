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
 * 登录审计实体，记录所有登录尝试。
 */
@Entity
@Table(name = "auth_login_audit", schema = "omni")
@Getter
@Setter
@AllArgsConstructor
@NoArgsConstructor
public class AuthLoginAudit {

    @Id
    private UUID id;

    @Column(name = "user_id", nullable = false)
    private UUID userId;

    @Column(nullable = false, length = 80)
    private String username;

    @Column(name = "login_result", nullable = false, length = 32)
    private String loginResult;

    @Column(name = "client_platform", nullable = false, length = 32)
    private String clientPlatform;

    @Column(name = "device_id", length = 128)
    private String deviceId;

    @Column(name = "device_name")
    private String deviceName;

    @Column(name = "ip_address", length = 45)
    private String ipAddress;

    @Column(name = "user_agent", length = 500)
    private String userAgent;

    @Column(name = "failure_reason")
    private String failureReason;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @PrePersist
    void fillDefaults() {
        if (id == null) {
            id = UUID.randomUUID();
        }
        if (createdAt == null) {
            createdAt = Instant.now();
        }
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (!(o instanceof AuthLoginAudit other)) return false;
        return id != null && id.equals(other.getId());
    }

    @Override
    public int hashCode() {
        return getClass().hashCode();
    }

    /**
     * 仅输出标识与登录结果，避免设备和网络信息进入日志。
     */
    @Override
    public String toString() {
        return "AuthLoginAudit{id=" + id + ", username=" + username + ", loginResult=" + loginResult + "}";
    }
}
