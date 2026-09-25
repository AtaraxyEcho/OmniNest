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
import com.omninest.modules.file.domain.EncryptionStatus;
import com.omninest.modules.file.domain.StorageClass;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

@Entity
@Table(name = "file_objects", schema = "omni")
@Getter
@Setter
@AllArgsConstructor
@NoArgsConstructor
public class FileObject {
    @Id
    private UUID id;

    @Column(name = "bucket_name", nullable = false, length = 80)
    private String bucketName;

    @Column(name = "object_key", nullable = false)
    private String objectKey;

    @Column(length = 64)
    private String sha256;

    @Column(name = "size_bytes", nullable = false)
    private long sizeBytes;

    @Column(name = "mime_type", length = 160)
    private String mimeType;

    @Column(name = "storage_class", nullable = false, length = 32)
    private String storageClass = StorageClass.STANDARD.getValue();

    @Column(name = "encryption_status", nullable = false, length = 32)
    private String encryptionStatus = EncryptionStatus.SERVER_SIDE.getValue();

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    @Version
    @Column(nullable = false)
    private long version;

    @PrePersist
    void fillDefaults() {
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
        if (!(o instanceof FileObject other)) {
            return false;
        }
        return id != null && id.equals(other.getId());
    }

    @Override
    public int hashCode() {
        return getClass().hashCode();
    }

    /**
     * 仅输出标识和元数据摘要，不完整展开 objectKey 与 sha256。
     */
    @Override
    public String toString() {
        String keySummary = objectKey == null ? null
                : objectKey.length() <= 64 ? objectKey : objectKey.substring(0, 64) + "...";
        String sha256Summary = sha256 == null ? null
                : sha256.length() <= 12 ? sha256 : sha256.substring(0, 12) + "...";
        return "FileObject{id=" + id + ", bucketName=" + bucketName
                + ", objectKey=" + keySummary + ", sha256=" + sha256Summary
                + ", sizeBytes=" + sizeBytes + ", mimeType=" + mimeType
                + ", storageClass=" + storageClass + ", encryptionStatus=" + encryptionStatus + "}";
    }
}
