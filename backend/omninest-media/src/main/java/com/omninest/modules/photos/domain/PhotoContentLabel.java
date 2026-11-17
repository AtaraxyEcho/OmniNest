package com.omninest.modules.photos.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

/**
 * 照片图像分析结构化标签，和用户手工标签分离保存。
 *
 * @author OmniNest
 */
@Entity
@Table(name = "photo_content_labels", schema = "omni")
@Getter
@Setter
@NoArgsConstructor
public class PhotoContentLabel {

    @Id
    private UUID id;

    @Column(name = "owner_user_id", nullable = false)
    private UUID ownerUserId;

    @Column(name = "photo_id", nullable = false)
    private UUID photoId;

    @Column(name = "run_id", nullable = false)
    private UUID runId;

    @Column(nullable = false, length = 32)
    private String namespace;

    @Column(name = "label_code", nullable = false, length = 100)
    private String labelCode;

    @Column(nullable = false)
    private float confidence;

    @Column(nullable = false, length = 64)
    private String source;

    @Column(name = "model_version", length = 128)
    private String modelVersion;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(columnDefinition = "jsonb")
    private List<Map<String, Object>> boxes;

    @Column(nullable = false, length = 32)
    private String state;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

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
        if (!(o instanceof PhotoContentLabel other)) {
            return false;
        }
        return id != null && id.equals(other.getId());
    }

    @Override
    public int hashCode() {
        return getClass().hashCode();
    }
}
