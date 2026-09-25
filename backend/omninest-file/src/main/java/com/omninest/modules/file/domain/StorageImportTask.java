package com.omninest.modules.file.domain;

import com.omninest.modules.file.domain.ImportTaskStatus;
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
 * 外部存储导入任务。
 * <p>
 * 记录从外部存储（rclone remote）导入文件到 MinIO 的异步任务状态和进度。
 *
 * @author OmniNest
 */
@Entity
@Table(name = "storage_import_tasks", schema = "omni")
@Getter
@Setter
@AllArgsConstructor
@NoArgsConstructor
public class StorageImportTask {
    @Id
    private UUID id;

    @Column(name = "owner_user_id", nullable = false)
    private UUID ownerUserId;

    @Column(name = "external_account_id", nullable = false)
    private UUID externalAccountId;

    @Column(name = "task_id")
    private UUID taskId;

    @Column(name = "source_path", nullable = false, length = 1024)
    private String sourcePath;

    @Column(name = "source_kind", nullable = false, length = 16)
    private String sourceKind = ImportSourceKind.FILE.getValue();

    @Column(name = "target_parent_id")
    private UUID targetParentId;

    @Column(name = "space_type", length = 16)
    private String spaceType = "PERSONAL";

    @Column(name = "rclone_job_id")
    private Integer rcloneJobId;

    @Column(name = "rclone_group", length = 128)
    private String rcloneGroup;

    @Column(name = "file_name", nullable = false, length = 255)
    private String fileName;

    @Column(name = "total_bytes", nullable = false)
    private long totalBytes;

    @Column(name = "transferred_bytes", nullable = false)
    private long transferredBytes;

    @Column(name = "speed_bytes", nullable = false)
    private long speedBytes;

    @Column(name = "total_files", nullable = false)
    private int totalFiles;

    @Column(name = "completed_files", nullable = false)
    private int completedFiles;

    @Column(name = "current_file_name", length = 1024)
    private String currentFileName;

    @Column(nullable = false, length = 32)
    private String status = ImportTaskStatus.QUEUED.getValue();

    @Column(name = "error_summary")
    private String errorSummary;

    @Column(name = "completed_file_id")
    private UUID completedFileId;

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

    @Override
    public boolean equals(Object o) {
        if (this == o) {
            return true;
        }
        if (!(o instanceof StorageImportTask other)) {
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
        return "StorageImportTask{id=" + id + ", ownerUserId=" + ownerUserId
                + ", status=" + status + ", fileName=" + fileName
                + ", totalBytes=" + totalBytes + ", transferredBytes=" + transferredBytes + "}";
    }
}
