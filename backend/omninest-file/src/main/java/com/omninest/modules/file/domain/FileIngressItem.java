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
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

/**
 * 记录隔离对象从待扫描到业务可用的文件入库生命周期。
 *
 * @author OmniNest
 */
@Entity
@Table(name = "file_ingress_items", schema = "omni")
@Getter
@Setter
@AllArgsConstructor
@NoArgsConstructor
public class FileIngressItem {
    @Id
    private UUID id;

    @Column(name = "owner_user_id", nullable = false)
    private UUID ownerUserId;

    @Column(name = "source_type", nullable = false, length = 24)
    private String sourceType;

    @Column(name = "source_task_id")
    private UUID sourceTaskId;

    @Column(name = "upload_session_id")
    private UUID uploadSessionId;

    @Column(name = "quarantine_bucket", nullable = false, length = 80)
    private String quarantineBucket;

    @Column(name = "quarantine_object_key", nullable = false)
    private String quarantineObjectKey;

    @Column(name = "target_bucket", nullable = false, length = 80)
    private String targetBucket;

    @Column(name = "target_object_key", nullable = false)
    private String targetObjectKey;

    @Column(name = "target_parent_id")
    private UUID targetParentId;

    @Column(name = "target_name", nullable = false, length = 255)
    private String targetName;

    @Column(name = "size_bytes", nullable = false)
    private long sizeBytes;

    @Column(length = 64)
    private String sha256;

    @Column(name = "mime_type", length = 160)
    private String mimeType;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 24)
    private FileIngressStatus status = FileIngressStatus.PENDING_SCAN;

    @Column(name = "scan_attempt_count", nullable = false)
    private int scanAttemptCount;

    @Column(name = "next_scan_at")
    private Instant nextScanAt;

    @Column(name = "threat_name", length = 255)
    private String threatName;

    @Column(name = "error_code", length = 64)
    private String errorCode;

    @Column(name = "result_file_node_id")
    private UUID resultFileNodeId;

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
        if (!(o instanceof FileIngressItem other)) {
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
        return "FileIngressItem{id=" + id + ", ownerUserId=" + ownerUserId
                + ", status=" + status + ", targetName=" + targetName
                + ", sizeBytes=" + sizeBytes + "}";
    }
}
