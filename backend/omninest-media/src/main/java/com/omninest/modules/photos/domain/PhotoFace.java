package com.omninest.modules.photos.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import jakarta.persistence.Version;
import java.time.Instant;
import java.util.UUID;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

/**
 * 照片人脸检测实体。
 * 存储 AI 检测到的人脸位置、嵌入向量和聚类归属。
 */
@Getter
@Setter
@NoArgsConstructor
@Entity
@Table(name = "photo_faces", schema = "omni")
public class PhotoFace {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @Column(name = "photo_id", nullable = false)
    private UUID photoId;

    @Column(name = "owner_user_id", nullable = false)
    private UUID ownerUserId;

    @Column(name = "bbox_x", nullable = false)
    private int bboxX;

    @Column(name = "bbox_y", nullable = false)
    private int bboxY;

    @Column(name = "bbox_w", nullable = false)
    private int bboxW;

    @Column(name = "bbox_h", nullable = false)
    private int bboxH;

    @Column(name = "embedding", columnDefinition = "bytea")
    private byte[] embedding;

    @Column(name = "cluster_id")
    private UUID clusterId;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    @Version
    @Column(nullable = false)
    private long version;

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
    void fillUpdatedAt() {
        updatedAt = Instant.now();
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) {
            return true;
        }
        if (!(o instanceof PhotoFace other)) {
            return false;
        }
        return id != null && id.equals(other.getId());
    }

    @Override
    public int hashCode() {
        return getClass().hashCode();
    }

    /**
     * 不输出 embedding 向量，避免大字段与敏感生物特征进入日志。
     */
    @Override
    public String toString() {
        return "PhotoFace{id=" + id + ", photoId=" + photoId + ", clusterId=" + clusterId + "}";
    }
}
