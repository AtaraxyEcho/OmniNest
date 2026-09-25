package com.omninest.modules.file.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;
import com.omninest.modules.file.domain.UploadStatus;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

@Entity
@Table(name = "file_upload_parts", schema = "omni")
@Getter
@Setter
@AllArgsConstructor
@NoArgsConstructor
public class FileUploadPart {
    @Id
    private UUID id;

    @Column(name = "upload_session_id", nullable = false)
    private UUID uploadSessionId;

    @Column(name = "owner_user_id", nullable = false)
    private UUID ownerUserId;

    @Column(name = "part_number", nullable = false)
    private int partNumber;

    @Column(name = "size_bytes", nullable = false)
    private long sizeBytes;

    @Column(name = "etag", length = 160)
    private String eTag;

    @Column(name = "status", nullable = false, length = 32)
    private String status = UploadStatus.PENDING.getValue();

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

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
        if (!(o instanceof FileUploadPart other)) {
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
        return "FileUploadPart{id=" + id + ", uploadSessionId=" + uploadSessionId
                + ", partNumber=" + partNumber + ", status=" + status + "}";
    }
}
