package com.omninest.modules.file.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import jakarta.persistence.Version;
import java.time.Instant;
import java.util.UUID;
import java.util.Objects;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import lombok.ToString;

@Entity
@Table(name = "share_links", schema = "omni")
@Getter
@Setter
@ToString(onlyExplicitlyIncluded = true)
@AllArgsConstructor
@NoArgsConstructor
public class ShareLink {
    @Id
    private UUID id;

    @Column(name = "owner_user_id", nullable = false)
    private UUID ownerUserId;

    @Column(name = "resource_type", nullable = false, length = 32)
    private String resourceType;

    @Column(name = "resource_id", nullable = false)
    private UUID resourceId;

    @Column(name = "token_hash", nullable = false, length = 128)
    private String tokenHash;

    /** 分享令牌密文：仅供所有者重新展示链接地址，公开校验仍以哈希为准。 */
    @Column(name = "token_cipher", columnDefinition = "text")
    private String tokenCipher;

    @Column(name = "password_hash", length = 255)
    private String passwordHash;

    @Column(name = "expires_at")
    private Instant expiresAt;

    @Column(name = "max_access_count")
    private Integer maxAccessCount;

    @Column(name = "access_count", nullable = false)
    private int accessCount;

    @Column(name = "include_location", nullable = false)
    private boolean includeLocation = true;

    @Column(name = "original_quality", nullable = false)
    private boolean originalQuality = true;

    @Column(name = "disabled_at")
    private Instant disabledAt;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    @Version
    @Column(nullable = false)
    private long version;

    @Override
    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof ShareLink that)) {
            return false;
        }
        return id != null && Objects.equals(id, that.id);
    }

    @Override
    public int hashCode() {
        // 稳定 hash：id 在 PrePersist 前可能为 null，不能参与 hash 否则入集合后丢失。
        return getClass().hashCode();
    }

    /**
     * 仅输出非敏感标识，避免 token/密码哈希进入日志。
     */
    @Override
    public String toString() {
        return "ShareLink{id=" + id + ", resourceType=" + resourceType
                + ", resourceId=" + resourceId + ", accessCount=" + accessCount + "}";
    }

    @PrePersist
    void fillCreatedFields() {
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
    void fillUpdatedAt() {
        updatedAt = Instant.now();
    }
}
