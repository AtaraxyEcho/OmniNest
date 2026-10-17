package com.omninest.modules.photos.domain;

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
 * 照片图像分析运行记录，保存模型版本和分析生命周期。
 *
 * @author OmniNest
 */
@Entity
@Table(name = "photo_content_analysis_runs", schema = "omni")
@Getter
@Setter
@NoArgsConstructor
public class PhotoContentAnalysisRun {

    @Id
    private UUID id;

    @Column(name = "owner_user_id", nullable = false)
    private UUID ownerUserId;

    @Column(name = "photo_id", nullable = false)
    private UUID photoId;

    @Column(name = "content_hash", length = 128)
    private String contentHash;

    @Column(name = "pipeline_version", nullable = false, length = 128)
    private String pipelineVersion;

    @Column(nullable = false, length = 32)
    private String status;

    @Column(name = "error_code", length = 64)
    private String errorCode;

    @Column(name = "error_message", length = 1000)
    private String errorMessage;

    @Column(name = "started_at")
    private Instant startedAt;

    @Column(name = "completed_at")
    private Instant completedAt;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    @Version
    @Column(nullable = false)
    private long version;

    @PrePersist
    void prePersist() {
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
    void preUpdate() {
        updatedAt = Instant.now();
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) {
            return true;
        }
        if (!(o instanceof PhotoContentAnalysisRun other)) {
            return false;
        }
        return id != null && id.equals(other.getId());
    }

    @Override
    public int hashCode() {
        return getClass().hashCode();
    }
}
