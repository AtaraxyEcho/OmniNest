package com.omninest.modules.video.domain;

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
 * 共享影视库与存储位置子目录的关联；ownerUserId 表示目录归属者，不代表唯一读取者。
 *
 * @author OmniNest
 */
@Getter
@Setter
@Entity
@Table(name = "video_library_sources", schema = "omni")
@AllArgsConstructor
@NoArgsConstructor
public class VideoLibrarySource {

    @Id
    private UUID id;

    @Column(name = "owner_user_id", nullable = false)
    private UUID ownerUserId;

    @Column(name = "storage_location_id", nullable = false)
    private UUID storageLocationId;

    @Column(nullable = false, length = 160)
    private String name;

    @Column(name = "relative_root", nullable = false)
    private String relativeRoot;

    @Column(name = "library_type", nullable = false, length = 24)
    private String libraryType;

    @Column(name = "import_policy", nullable = false, length = 32)
    private String importPolicy;

    @Column(name = "visibility_type", nullable = false, length = 24)
    private String visibilityType;

    @Column(nullable = false)
    private boolean enabled;

    @Column(name = "scan_status", nullable = false, length = 24)
    private String scanStatus;

    @Column(name = "health_status", nullable = false, length = 24)
    private String healthStatus;

    @Column(name = "last_scanned_at")
    private Instant lastScannedAt;

    @Column(name = "last_successful_scan_at")
    private Instant lastSuccessfulScanAt;

    @Column(name = "last_error_code", length = 80)
    private String lastErrorCode;

    @Column(name = "last_scanned_count", nullable = false)
    private int lastScannedCount;

    @Column(name = "last_created_count", nullable = false)
    private int lastCreatedCount;

    @Column(name = "last_candidate_count", nullable = false)
    private int lastCandidateCount;

    @Column(name = "last_missing_count", nullable = false)
    private int lastMissingCount;

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
        if (scanStatus == null) {
            scanStatus = "NEVER_SCANNED";
        }
        if (healthStatus == null) {
            healthStatus = enabled ? "AVAILABLE" : "DISABLED";
        }
        if (importPolicy == null) {
            importPolicy = "MANUAL_REVIEW";
        }
        if (visibilityType == null) {
            visibilityType = MediaLibraryVisibility.PRIVATE.name();
        }
        if (libraryType == null) {
            libraryType = MediaLibraryType.MOVIE.name();
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
        if (!(o instanceof VideoLibrarySource other)) {
            return false;
        }
        return id != null && id.equals(other.getId());
    }

    @Override
    public int hashCode() {
        return getClass().hashCode();
    }
}
