package com.omninest.modules.photos.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import jakarta.persistence.Version;
import java.time.Instant;
import java.time.LocalDate;
import java.util.UUID;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import org.hibernate.annotations.UuidGenerator;

/**
 * GeoNames 离线地理数据集版本。
 *
 * <p>负责数据集版本生命周期（IMPORTING → READY → PUBLISHED，失败进入 FAILED，
 * 被新版本替换的已发布数据集进入 ARCHIVED），不承载任务执行状态与进度。</p>
 *
 * @author OmniNest
 */
@Getter
@Setter
@NoArgsConstructor
@Entity
@Table(name = "geo_dataset", schema = "omni")
public class GeoDataset {

    /** 数据集状态：导入中。 */
    public static final String STATUS_IMPORTING = "IMPORTING";
    /** 数据集状态：数据验证通过，待发布。 */
    public static final String STATUS_READY = "READY";
    /** 数据集状态：已发布，线上索引当前版本。 */
    public static final String STATUS_PUBLISHED = "PUBLISHED";
    /** 数据集状态：被新版本替换的历史版本。 */
    public static final String STATUS_ARCHIVED = "ARCHIVED";
    /** 数据集状态：导入失败。 */
    public static final String STATUS_FAILED = "FAILED";

    @Id
    @UuidGenerator
    private UUID id;

    /** 数据集版本号，全局唯一 */
    @Column(name = "dataset_version", nullable = false, length = 64)
    private String datasetVersion;

    /** GeoNames dump 日期 */
    @Column(name = "source_dump_date", nullable = false)
    private LocalDate sourceDumpDate;

    /** 数据集类型，如 cities5000 */
    @Column(name = "dataset_type", nullable = false, length = 32)
    private String datasetType;

    /** 源文件摘要，用于追溯 */
    @Column(name = "source_hash", length = 128)
    private String sourceHash;

    /** 数据集状态 */
    @Column(nullable = false, length = 20)
    private String status;

    /** 发布时间 */
    @Column(name = "published_at")
    private Instant publishedAt;

    /** 创建时间 */
    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    /** 更新时间 */
    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    /** 乐观锁版本号 */
    @Version
    @Column(nullable = false)
    private long version;

    @PrePersist
    void prePersist() {
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
        if (!(o instanceof GeoDataset other)) {
            return false;
        }
        return id != null && id.equals(other.getId());
    }

    @Override
    public int hashCode() {
        return getClass().hashCode();
    }
}
