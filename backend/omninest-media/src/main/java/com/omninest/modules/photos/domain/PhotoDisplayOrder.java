package com.omninest.modules.photos.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import jakarta.persistence.Version;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

/**
 * 照片多视图上下文（按日分组、收藏等）的自定义展示顺序实体。
 */
@Entity
@Table(name = "photo_display_orders", schema = "omni")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
public class PhotoDisplayOrder {
    @Id
    private UUID id;

    @Column(name = "owner_user_id", nullable = false)
    private UUID ownerUserId;

    @Column(name = "context_key", nullable = false, length = 128)
    private String contextKey;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "ordered_photo_ids", columnDefinition = "jsonb", nullable = false)
    private List<UUID> orderedPhotoIds = new ArrayList<>();

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    @Version
    @Column(nullable = false)
    private Long version;

    @PrePersist
    void prePersist() {
        if (id == null) {
            id = UUID.randomUUID();
        }
        if (orderedPhotoIds == null) {
            orderedPhotoIds = new ArrayList<>();
        }
        updatedAt = Instant.now();
    }

    @PreUpdate
    void preUpdate() {
        if (orderedPhotoIds == null) {
            orderedPhotoIds = new ArrayList<>();
        }
        updatedAt = Instant.now();
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) {
            return true;
        }
        if (!(o instanceof PhotoDisplayOrder other)) {
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
        return "PhotoDisplayOrder{id=" + id + ", ownerUserId=" + ownerUserId
                + ", contextKey=" + contextKey + "}";
    }
}
