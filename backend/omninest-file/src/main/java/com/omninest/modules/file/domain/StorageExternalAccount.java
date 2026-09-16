package com.omninest.modules.file.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

/**
 * 用户外部存储连接账户。
 *
 * @author OmniNest
 */
@Entity
@Table(name = "storage_external_accounts", schema = "omni")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
public class StorageExternalAccount {
    @Id
    private UUID id;

    @Column(name = "owner_user_id", nullable = false)
    private UUID ownerUserId;

    @Column(nullable = false, length = 64)
    private String provider;

    @Column(name = "display_name", nullable = false, length = 160)
    private String displayName;

    @Column(name = "encrypted_credentials", nullable = false)
    private String encryptedCredentials;

    @Column(nullable = false, length = 32)
    private String status = ExternalStorageStatus.ACTIVE.getValue();

    @Column(name = "last_error_code", length = 64)
    private String lastErrorCode;

    @Column(name = "last_checked_at")
    private Instant lastCheckedAt;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

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
}
