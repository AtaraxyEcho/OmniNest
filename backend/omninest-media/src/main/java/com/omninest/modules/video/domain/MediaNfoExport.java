package com.omninest.modules.video.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
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

@Entity
@Table(name = "media_nfo_exports", schema = "omni")
@Getter
@Setter
@AllArgsConstructor
@NoArgsConstructor
public class MediaNfoExport {
    @Id
    private UUID id;

    @Column(name = "owner_user_id", nullable = false)
    private UUID ownerUserId;

    @Column(name = "video_item_id", nullable = false)
    private UUID videoItemId;

    @Column(name = "export_path", nullable = false)
    private String exportPath;

    @Column(name = "status", nullable = false, length = 32)
    // 默认值用字面量，避免 Hibernate 元模型初始化时强依赖枚举类加载。
    private String status = "PENDING";

    @Column(name = "error_summary")
    private String errorSummary;

    @Column(name = "exported_at")
    private Instant exportedAt;

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
        if (!(o instanceof MediaNfoExport other)) {
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
        return "MediaNfoExport{id=" + id + ", videoItemId=" + videoItemId + ", status=" + status + "}";
    }
}
