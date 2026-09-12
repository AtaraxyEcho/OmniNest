package com.omninest.modules.user.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import jakarta.persistence.Version;
import java.time.Instant;
import java.util.UUID;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

/**
 * 两步验证 TOTP 凭据，每用户至多一条。
 *
 * <p>秘钥以 Base32 明文存储，与密码哈希同库同险；丢失认证器时可通过删除本表记录恢复密码直登。</p>
 *
 * @author OmniNest
 */
@Entity
@Table(name = "auth_totp_credentials", schema = "omni")
@Getter
@Setter
@NoArgsConstructor
public class AuthTotpCredential {

    @Id
    private UUID id;

    @Column(name = "user_id", nullable = false)
    private UUID userId;

    @Column(nullable = false, length = 64)
    private String secret;

    @Column(nullable = false)
    private boolean enabled;

    @Column(name = "confirmed_at")
    private Instant confirmedAt;

    @Column(name = "last_used_step")
    private Long lastUsedStep;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    @Version
    @Column(nullable = false)
    private long version;

    @PrePersist
    void fillDefaults() {
        if (id == null) {
            id = UUID.randomUUID();
        }
        Instant now = Instant.now();
        if (createdAt == null) {
            createdAt = now;
        }
        if (updatedAt == null) {
            updatedAt = now;
        }
    }

    @PreUpdate
    void touchUpdatedAt() {
        updatedAt = Instant.now();
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (!(o instanceof AuthTotpCredential other)) return false;
        return id != null && id.equals(other.getId());
    }

    @Override
    public int hashCode() {
        return getClass().hashCode();
    }
}
