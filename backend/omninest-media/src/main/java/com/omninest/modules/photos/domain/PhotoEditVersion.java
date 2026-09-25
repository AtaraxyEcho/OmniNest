package com.omninest.modules.photos.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import jakarta.persistence.Version;
import java.time.Instant;
import java.util.Map;
import java.util.UUID;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

/**
 * 照片编辑版本实体，记录每次非破坏性编辑操作。
 */
@Entity
@Table(name = "photo_edit_versions", schema = "omni")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
public class PhotoEditVersion {

    @Id
    private UUID id;

    @Column(name = "owner_user_id", nullable = false)
    private UUID ownerUserId;

    @Column(name = "photo_id", nullable = false)
    private UUID photoId;

    @Column(name = "version_number", nullable = false)
    private int versionNumber = 1;

    @Column(name = "edit_type", nullable = false, length = 32)
    private String editType;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "edit_params", columnDefinition = "jsonb", nullable = false)
    private Map<String, Object> editParams = Map.of();

    @Column(name = "file_id", nullable = false)
    private UUID fileId;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @Version
    @Column(nullable = false)
    private long version;

    @PrePersist
    void prePersist() {
        if (id == null) id = UUID.randomUUID();
        Instant now = Instant.now();
        if (createdAt == null) createdAt = now;
    }

    @PreUpdate
    void preUpdate() {
        // 仅 updatedAt 需要更新，但此实体无 updatedAt 字段
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) {
            return true;
        }
        if (!(o instanceof PhotoEditVersion other)) {
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
        return "PhotoEditVersion{id=" + id + ", photoId=" + photoId + ", versionNumber=" + versionNumber
                + ", editType=" + editType + "}";
    }
}
