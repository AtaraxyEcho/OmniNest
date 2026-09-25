package com.omninest.modules.file.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import jakarta.persistence.Version;
import java.time.Instant;
import java.util.UUID;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.domain.UploadStatus;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

@Entity
@Table(name = "file_upload_sessions", schema = "omni")
@Getter
@Setter
@AllArgsConstructor
@NoArgsConstructor
public class FileUploadSession {
    @Id
    private UUID id;

    @Column(name = "owner_user_id", nullable = false)
    private UUID ownerUserId;

    @Column(name = "target_parent_id")
    private UUID targetParentId;

    @Column(name = "file_name", nullable = false, length = 255)
    private String fileName;

    @Column(name = "total_size_bytes", nullable = false)
    private long totalSizeBytes;

    @Column(name = "part_size_bytes", nullable = false)
    private int partSizeBytes;

    @Column(name = "total_parts", nullable = false)
    private int totalParts = 1;

    @Column(name = "uploaded_parts", nullable = false)
    private int uploadedParts;

    @Column(name = "mime_type", length = 160)
    private String mimeType;

    @Column(length = 64)
    private String sha256;

    @Column(nullable = false, length = 32)
    private String status = UploadStatus.CREATED.getValue();

    @Column(name = "upload_id")
    private String uploadId;

    @Column(name = "target_bucket", nullable = false, length = 80)
    private String targetBucket;

    @Column(name = "target_object_key", nullable = false)
    private String targetObjectKey;

    @Column(name = "ingress_item_id")
    private UUID ingressItemId;

    @Column(name = "result_file_node_id")
    private UUID resultFileNodeId;

    @Column(name = "result_object_id")
    private UUID resultObjectId;

    @Column(name = "completion_task_id")
    private UUID completionTaskId;

    @Column(name = "quota_reservation_id")
    private UUID quotaReservationId;

    @Column(name = "expires_at", nullable = false)
    private Instant expiresAt;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    @Version
    @Column(nullable = false)
    private long version;

    @Enumerated(EnumType.STRING)
    @Column(name = "space_type", nullable = false, length = 20)
    private SpaceType spaceType = SpaceType.PERSONAL;

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
        if (!(o instanceof FileUploadSession other)) {
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
        return "FileUploadSession{id=" + id + ", ownerUserId=" + ownerUserId
                + ", fileName=" + fileName + ", status=" + status
                + ", totalSizeBytes=" + totalSizeBytes + ", uploadedParts=" + uploadedParts + "}";
    }
}
