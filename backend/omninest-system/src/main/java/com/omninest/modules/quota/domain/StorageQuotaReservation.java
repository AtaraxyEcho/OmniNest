package com.omninest.modules.quota.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import jakarta.persistence.Version;
import java.time.Instant;
import java.util.UUID;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

/**
 * 持久化一次文件写入所占用的存储配额预留。
 *
 * @author OmniNest
 */
@Entity
@Table(name = "storage_quota_reservations", schema = "omni")
@Getter
@Setter
@AllArgsConstructor
@NoArgsConstructor
public class StorageQuotaReservation {
    @Id
    private UUID id;

    @Column(name = "owner_user_id", nullable = false)
    private UUID ownerUserId;

    @Column(name = "source_type", nullable = false, length = 32)
    private String sourceType;

    @Column(name = "source_id", nullable = false)
    private UUID sourceId;

    @Column(name = "reserved_bytes", nullable = false)
    private long reservedBytes;

    @Column(name = "committed_bytes", nullable = false)
    private long committedBytes;

    @Column(name = "quota_applied", nullable = false)
    private boolean quotaApplied;

    @Column(nullable = false, length = 24)
    private String status;

    @Column(name = "expires_at", nullable = false)
    private Instant expiresAt;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    @Version
    @Column(nullable = false)
    private long version;

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

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (!(o instanceof StorageQuotaReservation other)) return false;
        return id != null && id.equals(other.getId());
    }

    @Override
    public int hashCode() {
        return getClass().hashCode();
    }

    @Override
    public String toString() {
        return "StorageQuotaReservation{id=" + id + ", ownerUserId=" + ownerUserId
                + ", sourceId=" + sourceId + ", status=" + status + "}";
    }
}
