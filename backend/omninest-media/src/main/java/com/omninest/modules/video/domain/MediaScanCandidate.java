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
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

/**
 * 媒体发现阶段生成的安全候选项。
 */
@Getter
@Setter
@Entity
@Table(name = "media_scan_candidates", schema = "omni")
@NoArgsConstructor
public class MediaScanCandidate {

    @Id
    private UUID id;

    @Column(name = "owner_user_id", nullable = false)
    private UUID ownerUserId;

    @Column(name = "scan_run_id", nullable = false)
    private UUID scanRunId;

    @Column(name = "library_source_id", nullable = false)
    private UUID librarySourceId;

    @Column(name = "relative_path", nullable = false)
    private String relativePath;

    @Column(name = "file_name", nullable = false, length = 512)
    private String fileName;

    @Column(name = "size_bytes", nullable = false)
    private long sizeBytes;

    @Column(name = "modified_at")
    private Instant modifiedAt;

    @Column(name = "provider_etag", length = 160)
    private String providerEtag;

    @Column(name = "candidate_type", nullable = false, length = 24)
    private String candidateType;

    @Column(name = "group_id", nullable = false)
    private UUID groupId;

    @Column(name = "group_title", nullable = false, length = 512)
    private String groupTitle;

    @Column(name = "season_number")
    private Integer seasonNumber;

    @Column(name = "episode_number")
    private Integer episodeNumber;

    @Column(name = "match_status", nullable = false, length = 24)
    private String matchStatus;

    @Column(nullable = false)
    private boolean selected;

    @Column(name = "apply_status", nullable = false, length = 24)
    private String applyStatus;

    @Column(name = "existing_file_node_id")
    private UUID existingFileNodeId;

    @Column(name = "applied_file_node_id")
    private UUID appliedFileNodeId;

    @Column(name = "reason_code", length = 80)
    private String reasonCode;

    @Column(name = "error_summary", length = 500)
    private String errorSummary;

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
        if (matchStatus == null) {
            matchStatus = "NEW";
        }
        if (applyStatus == null) {
            applyStatus = "PENDING";
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
        if (!(o instanceof MediaScanCandidate other)) {
            return false;
        }
        return id != null && id.equals(other.getId());
    }

    @Override
    public int hashCode() {
        return getClass().hashCode();
    }
}
