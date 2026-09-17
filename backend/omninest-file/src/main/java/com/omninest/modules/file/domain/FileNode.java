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
import com.omninest.modules.file.domain.SourceType;
import com.omninest.modules.file.domain.SpaceType;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

@Entity
@Table(name = "file_nodes", schema = "omni")
@Getter
@Setter
@AllArgsConstructor
@NoArgsConstructor
public class FileNode {
    @Id
    private UUID id;

    @Column(name = "owner_user_id", nullable = false)
    private UUID ownerUserId;

    @Column(name = "parent_id")
    private UUID parentId;

    @Column(name = "node_type", nullable = false, length = 16)
    private String nodeType;

    @Column(nullable = false, length = 255)
    private String name;

    @Column(name = "normalized_path", nullable = false)
    private String normalizedPath;

    @Column(name = "mime_type", length = 160)
    private String mimeType;

    /** 业务分类，仅 FILE 节点写入；列表接口按此在库内过滤分页。 */
    @Column(length = 32)
    private String category;

    @Column(name = "size_bytes", nullable = false)
    private long sizeBytes;

    @Column(name = "current_object_id")
    private UUID currentObjectId;

    @Column(name = "source_type", nullable = false, length = 32)
    private String sourceType = SourceType.LOCAL.getValue();

    @Column(name = "is_deleted", nullable = false)
    private boolean deleted;

    @Column(name = "deleted_at")
    private Instant deletedAt;

    @Column(name = "deleted_by")
    private UUID deletedBy;

    @Enumerated(EnumType.STRING)
    @Column(name = "purge_state", nullable = false, length = 24)
    private FilePurgeState purgeState = FilePurgeState.NONE;

    @Column(name = "purge_task_id")
    private UUID purgeTaskId;

    @Column(name = "purge_requested_at")
    private Instant purgeRequestedAt;

    @Column(nullable = false)
    private boolean shared;

    @Column(name = "shared_at")
    private Instant sharedAt;

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

    @Column(name = "uploaded_by")
    private UUID uploadedBy;

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
        refreshCategory();
    }

    @PreUpdate
    void fillUpdatedAt() {
        updatedAt = Instant.now();
        refreshCategory();
    }

    private void refreshCategory() {
        category = FileTypeCategories.resolve(name, mimeType, nodeType);
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (!(o instanceof FileNode other)) return false;
        return id != null && id.equals(other.getId());
    }

    @Override
    public int hashCode() {
        return getClass().hashCode();
    }
}
