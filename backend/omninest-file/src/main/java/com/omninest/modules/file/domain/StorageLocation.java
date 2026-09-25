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
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

/**
 * 由部署配置提供物理根目录的存储位置。
 *
 * @author OmniNest
 */
@Getter
@Setter
@Entity
@Table(name = "storage_locations", schema = "omni")
@AllArgsConstructor
@NoArgsConstructor
public class StorageLocation {

    @Id
    private UUID id;

    @Column(nullable = false, length = 160)
    private String name;

    @Column(name = "provider_type", nullable = false, length = 32)
    private String providerType;

    @Column(name = "management_mode", nullable = false, length = 24)
    private String managementMode;

    @Column(name = "mount_key", nullable = false, length = 80)
    private String mountKey;

    @Column(name = "relative_root", nullable = false)
    private String relativeRoot;

    @Column(name = "scope_type", nullable = false, length = 24)
    private String scopeType;

    @Column(name = "scope_id")
    private UUID scopeId;

    @Column(nullable = false)
    private boolean enabled;

    @Column(name = "created_by", nullable = false)
    private UUID createdBy;

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
        if (this == o) {
            return true;
        }
        if (!(o instanceof StorageLocation other)) {
            return false;
        }
        return id != null && id.equals(other.getId());
    }

    @Override
    public int hashCode() {
        return getClass().hashCode();
    }

    @Override
    public String toString() {
        return "StorageLocation{id=" + id + ", name=" + name
                + ", providerType=" + providerType + ", managementMode=" + managementMode
                + ", mountKey=" + mountKey + ", enabled=" + enabled + "}";
    }
}
