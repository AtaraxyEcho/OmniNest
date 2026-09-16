package com.omninest.modules.file.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;
import com.omninest.modules.task.domain.TaskStatus;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Entity
@Table(name = "download_offline_tasks", schema = "omni")
@Data
@AllArgsConstructor
@NoArgsConstructor
public class DownloadOfflineTask {
    @Id
    private UUID id;

    @Column(name = "owner_user_id", nullable = false)
    private UUID ownerUserId;

    @Column(name = "source_uri", nullable = false)
    private String sourceUri;

    @Column(name = "target_parent_id")
    private UUID targetParentId;

    @Column(name = "space_type", nullable = false, length = 16)
    private String spaceType = "PERSONAL";

    @Column(name = "task_id")
    private UUID taskId;

    @Column(name = "aria2_gid", length = 32)
    private String aria2Gid;

    @Column(name = "file_name", length = 255)
    private String fileName;

    @Column(name = "total_bytes", nullable = false)
    private long totalBytes;

    @Column(name = "completed_bytes", nullable = false)
    private long completedBytes;

    @Column(name = "download_speed_bytes", nullable = false)
    private long downloadSpeedBytes;

    @Column(name = "error_summary", columnDefinition = "text")
    private String errorSummary;

    @Column(name = "completed_file_id")
    private UUID completedFileId;

    @Column(name = "completed_at")
    private Instant completedAt;

    @Column(nullable = false, length = 32)
    private String status = TaskStatus.QUEUED.getValue();

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
