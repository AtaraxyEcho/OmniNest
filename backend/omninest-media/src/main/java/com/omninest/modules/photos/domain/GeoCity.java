package com.omninest.modules.photos.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

/**
 * GeoNames 城市数据（离线逆地理编码用）。
 *
 * <p>按数据集版本分行存储，主键为代理 id，(datasetId, geonameId) 唯一；中英文名称分列保存，
 * 地理数据层不感知展示 locale。</p>
 *
 * @author OmniNest
 */
@Getter
@Setter
@NoArgsConstructor
@Entity
@Table(name = "geo_cities", schema = "omni",
        uniqueConstraints = @UniqueConstraint(
                name = "uk_geo_cities_dataset_geoname",
                columnNames = {"dataset_id", "geoname_id"}))
public class GeoCity {

    @Id
    @Column(name = "id", nullable = false)
    private UUID id;

    @Column(name = "dataset_id", nullable = false)
    private UUID datasetId;

    @Column(name = "geoname_id", nullable = false)
    private Long geonameId;

    /** GeoNames 主名称（国际主名称） */
    @Column(name = "name", nullable = false, length = 200)
    private String name;

    /** 城市中文名，选优自 alternateNames */
    @Column(name = "name_zh", length = 200)
    private String nameZh;

    @Column(name = "country_code", nullable = false, length = 2)
    private String countryCode;

    /** 国家英文名，取自 countryInfo */
    @Column(name = "country_name_en", length = 200)
    private String countryNameEn;

    /** 国家中文名 */
    @Column(name = "country_name_zh", length = 200)
    private String countryNameZh;

    /** 一级行政区英文名，取自 admin1CodesASCII */
    @Column(name = "province_name_en", length = 200)
    private String provinceNameEn;

    /** 一级行政区中文名 */
    @Column(name = "province_name_zh", length = 200)
    private String provinceNameZh;

    @Column(name = "latitude", nullable = false, precision = 10, scale = 7)
    private BigDecimal latitude;

    @Column(name = "longitude", nullable = false, precision = 10, scale = 7)
    private BigDecimal longitude;

    @Column(name = "population", nullable = false)
    private long population;

    @Column(name = "feature_code", length = 10)
    private String featureCode;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @PrePersist
    void prePersist() {
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
        if (!(o instanceof GeoCity other)) {
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
        return "GeoCity{id=" + id + ", datasetId=" + datasetId + ", geonameId=" + geonameId
                + ", name=" + name + ", countryCode=" + countryCode + "}";
    }
}
