package com.omninest.modules.photos.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import jakarta.persistence.Version;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

@Entity
@Table(name = "photo_items", schema = "omni")
@Data
@NoArgsConstructor
@AllArgsConstructor
public class PhotoItem {
    @Id
    private UUID id;

    @Column(name = "owner_user_id", nullable = false)
    private UUID ownerUserId;

    @Column(name = "file_node_id", nullable = false)
    private UUID fileNodeId;

    @Column(nullable = false, length = 500)
    private String title;

    @Column(columnDefinition = "text")
    private String description;

    private Integer width;

    private Integer height;

    private Integer orientation;

    @Column(name = "date_taken")
    private Instant dateTaken;

    @Column(name = "camera_make", length = 120)
    private String cameraMake;

    @Column(name = "camera_model", length = 120)
    private String cameraModel;

    @Column(length = 32)
    private String aperture;

    @Column(name = "shutter_speed", length = 32)
    private String shutterSpeed;

    private Integer iso;

    @Column(name = "focal_length", length = 32)
    private String focalLength;

    @Column(length = 32)
    private String flash;

    @Column(name = "white_balance", length = 32)
    private String whiteBalance;

    @Column(name = "metering_mode", length = 32)
    private String meteringMode;

    @Column(name = "lens_model", length = 120)
    private String lensModel;

    @Column(name = "gps_latitude", precision = 10, scale = 7)
    private BigDecimal gpsLatitude;

    @Column(name = "gps_longitude", precision = 10, scale = 7)
    private BigDecimal gpsLongitude;

    @Column(length = 16)
    private String format;

    @Column(name = "file_size", nullable = false)
    private long fileSize;

    @Column(name = "cover_file_id")
    private UUID coverFileId;

    @Column(name = "metadata_status", nullable = false, length = 32)
    private String metadataStatus = "PENDING";

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "provider_metadata", nullable = false, columnDefinition = "jsonb")
    private Map<String, Object> providerMetadata = new HashMap<>();

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "gps_location", columnDefinition = "jsonb")
    private Map<String, Object> gpsLocation = new HashMap<>();

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    /** 进入回收站的时间；NULL 表示未删除。 */
    @Column(name = "deleted_at")
    private Instant deletedAt;

    /**
     * 动态照片状态：NULL 表示历史照片或非动态照片；
     * DETECTED 表示已识别运动段待提取；READY 表示运动视频派生资产可用；FAILED 表示提取失败。
     */
    @Column(name = "motion_state", length = 16)
    private String motionState;

    /** 动态照片提取出的运动视频派生资产文件节点；仅 READY 状态有值。 */
    @Column(name = "motion_video_file_node_id")
    private UUID motionVideoFileNodeId;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    @Version
    @Column(nullable = false)
    private long version;

    @PrePersist
    void prePersist() {
        if (id == null) id = UUID.randomUUID();
        Instant now = Instant.now();
        if (createdAt == null) createdAt = now;
        if (updatedAt == null) updatedAt = now;
    }

    @PreUpdate
    void preUpdate() {
        updatedAt = Instant.now();
    }
}
