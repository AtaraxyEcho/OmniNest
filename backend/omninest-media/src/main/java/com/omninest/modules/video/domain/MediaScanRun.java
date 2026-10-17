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
 * 本地媒体来源的一次发现、审核和入库运行。
 *
 * <p>运行记录是前端恢复审核状态和 Worker 断点续作的稳定边界，不保存宿主机绝对路径。</p>
 */
@Getter
@Setter
@Entity
@Table(name = "media_scan_runs", schema = "omni")
@NoArgsConstructor
public class MediaScanRun {

    @Id
    private UUID id;

    @Column(name = "owner_user_id", nullable = false)
    private UUID ownerUserId;

    @Column(name = "library_source_id", nullable = false)
    private UUID librarySourceId;

    @Column(name = "discovery_task_id")
    private UUID discoveryTaskId;

    @Column(name = "apply_task_id")
    private UUID applyTaskId;

    @Column(nullable = false)
    private long generation;

    @Column(name = "selection_revision", nullable = false)
    private long selectionRevision;

    @Column(nullable = false, length = 24)
    private String status;

    @Column(nullable = false, length = 24)
    private String phase;

    @Column(name = "discovered_count", nullable = false)
    private int discoveredCount;

    @Column(name = "candidate_count", nullable = false)
    private int candidateCount;

    @Column(name = "existing_count", nullable = false)
    private int existingCount;

    @Column(name = "conflict_count", nullable = false)
    private int conflictCount;

    @Column(name = "unmatched_count", nullable = false)
    private int unmatchedCount;

    @Column(name = "missing_count", nullable = false)
    private int missingCount;

    @Column(name = "selected_count", nullable = false)
    private int selectedCount;

    @Column(name = "applied_count", nullable = false)
    private int appliedCount;

    @Column(name = "failed_count", nullable = false)
    private int failedCount;

    @Column(name = "started_at")
    private Instant startedAt;

    @Column(name = "finished_at")
    private Instant finishedAt;

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
        if (status == null) {
            status = "QUEUED";
        }
        if (phase == null) {
            phase = "DISCOVERY";
        }
        if (generation <= 0) {
            generation = 1;
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
        if (!(o instanceof MediaScanRun other)) {
            return false;
        }
        return id != null && id.equals(other.getId());
    }

    @Override
    public int hashCode() {
        return getClass().hashCode();
    }
}
