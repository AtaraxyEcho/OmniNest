package com.omninest.modules.file.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;
import jakarta.persistence.Version;
import java.time.Instant;
import java.util.UUID;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

/**
 * 文件历史版本对象引用。
 *
 * @author OmniNest
 */
@Entity
@Table(name = "file_versions", schema = "omni")
@Getter
@Setter
@AllArgsConstructor
@NoArgsConstructor
public class FileVersion {
    @Id
    private UUID id;

    @Column(name = "file_node_id", nullable = false)
    private UUID fileNodeId;

    @Column(name = "object_id", nullable = false)
    private UUID objectId;

    @Column(name = "version_no", nullable = false)
    private int versionNo;

    @Column(name = "minio_version_id", length = 255)
    private String minioVersionId;

    @Column(name = "change_type", nullable = false, length = 32)
    private String changeType;

    @Column(name = "created_by")
    private UUID createdBy;

    @Column(name = "remark", length = 500)
    private String remark;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @Version
    @Column(nullable = false)
    private long version;

    @PrePersist
    void fillDefaults() {
        if (id == null) {
            id = UUID.randomUUID();
        }
        if (createdAt == null) {
            createdAt = Instant.now();
        }
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) {
            return true;
        }
        if (!(o instanceof FileVersion other)) {
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
        return "FileVersion{id=" + id + ", fileNodeId=" + fileNodeId
                + ", objectId=" + objectId + ", versionNo=" + versionNo
                + ", changeType=" + changeType + "}";
    }
}
