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
 * 自适应媒体处理批次及其检查点。
 */
@Getter
@Setter
@Entity
@Table(name = "media_scan_batches", schema = "omni")
@NoArgsConstructor
public class MediaScanBatch {

    @Id
    private UUID id;

    @Column(name = "owner_user_id", nullable = false)
    private UUID ownerUserId;

    @Column(name = "scan_run_id", nullable = false)
    private UUID scanRunId;

    @Column(nullable = false, length = 24)
    private String phase;

    @Column(name = "batch_no", nullable = false)
    private int batchNo;

    @Column(nullable = false, length = 24)
    private String status;

    @Column(name = "planned_size", nullable = false)
    private int plannedSize;

    @Column(name = "item_count", nullable = false)
    private int itemCount;

    @Column(name = "success_count", nullable = false)
    private int successCount;

    @Column(name = "failure_count", nullable = false)
    private int failureCount;

    @Column(name = "payload_bytes", nullable = false)
    private long payloadBytes;

    @Column(name = "duration_millis", nullable = false)
    private long durationMillis;

    @Column(name = "next_suggested_size", nullable = false)
    private int nextSuggestedSize;

    @Column(name = "retry_count", nullable = false)
    private int retryCount;

    @Column(name = "last_error_summary", length = 500)
    private String lastErrorSummary;

    @Column(name = "started_at", nullable = false)
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
        if (startedAt == null) {
            startedAt = now;
        }
        if (createdAt == null) {
            createdAt = now;
        }
        if (updatedAt == null) {
            updatedAt = now;
        }
        if (status == null) {
            status = "RUNNING";
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
        if (!(o instanceof MediaScanBatch other)) {
            return false;
        }
        return id != null && id.equals(other.getId());
    }

    @Override
    public int hashCode() {
        return getClass().hashCode();
    }
}
