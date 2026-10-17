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
 * 文件节点到外部内容的只读引用。
 *
 * @author OmniNest
 */
@Getter
@Setter
@Entity
@Table(name = "file_content_refs", schema = "omni")
@AllArgsConstructor
@NoArgsConstructor
public class FileContentRef {

    @Id
    private UUID id;

    @Column(name = "owner_user_id", nullable = false)
    private UUID ownerUserId;

    @Column(name = "file_node_id", nullable = false)
    private UUID fileNodeId;

    @Column(name = "storage_location_id", nullable = false)
    private UUID storageLocationId;

    @Column(name = "relative_path", nullable = false)
    private String relativePath;

    @Column(name = "provider_etag", length = 160)
    private String providerEtag;

    @Column(name = "size_bytes", nullable = false)
    private long sizeBytes;

    @Column(name = "modified_at")
    private Instant modifiedAt;

    @Column(name = "availability_status", nullable = false, length = 24)
    private String availabilityStatus;

    @Column(name = "last_seen_at", nullable = false)
    private Instant lastSeenAt;

    @Column(name = "last_seen_scan_run_id")
    private UUID lastSeenScanRunId;

    @Column(name = "missing_since")
    private Instant missingSince;

    @Column(name = "missing_confirmations", nullable = false)
    private int missingConfirmations;

    @Column(name = "last_availability_run_id")
    private UUID lastAvailabilityRunId;

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
        if (lastSeenAt == null) {
            lastSeenAt = now;
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
        if (!(o instanceof FileContentRef other)) {
            return false;
        }
        return id != null && id.equals(other.getId());
    }

    @Override
    public int hashCode() {
        return getClass().hashCode();
    }
}
