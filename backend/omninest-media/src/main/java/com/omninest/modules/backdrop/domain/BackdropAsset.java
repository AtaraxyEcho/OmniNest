package com.omninest.modules.backdrop.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Convert;
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
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

/**
 * 跨端背景素材实体。
 *
 * <p>素材与 MinIO 对象的一致性由应用层服务与对账任务维护；width、height、duration_ms
 * 为客户端上报的展示字段，不参与配额、安全与权限判断。</p>
 *
 * @author OmniNest
 */
@Entity
@Table(name = "backdrop_assets", schema = "omni")
@Getter
@Setter
@NoArgsConstructor
public class BackdropAsset {

    /** 素材唯一标识，主键。 */
    @Id
    private UUID id;

    /** 所属用户 ID，关联 auth_users。 */
    @Column(name = "owner_user_id", nullable = false)
    private UUID ownerUserId;

    /** 素材展示标题。 */
    @Column(name = "title", nullable = false, length = 200)
    private String title;

    /** 媒体类型，持久化为小写 image / gif / video。 */
    @Convert(converter = BackdropMediaTypeConverter.class)
    @Column(name = "media_type", nullable = false, length = 16)
    private BackdropMediaType mediaType;

    /** 原始素材文件节点 ID,关联 file_nodes;行先于对象顺序下,PROCESSING 在途阶段为空,READY 必有值。 */
    @Column(name = "file_node_id")
    private UUID fileNodeId;

    /** 缩略图文件节点 ID，GIF 与视频为空。 */
    @Column(name = "thumb_file_id")
    private UUID thumbFileId;

    /** 客户端上报的展示宽度，非可信字段。 */
    @Column(name = "width")
    private Integer width;

    /** 客户端上报的展示高度，非可信字段。 */
    @Column(name = "height")
    private Integer height;

    /** 客户端上报的展示时长（毫秒），非可信字段。 */
    @Column(name = "duration_ms")
    private Integer durationMs;

    /** 素材文件大小，单位字节，服务端计算。 */
    @Column(name = "file_size", nullable = false)
    private long fileSize;

    /** 服务端流式计算的 SHA256，与 owner_user_id 组成用户级去重键。 */
    @Column(name = "sha256", nullable = false, length = 64)
    private String sha256;

    /** 生命周期状态。 */
    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 16)
    private BackdropAssetStatus status = BackdropAssetStatus.PROCESSING;

    /** 失败原因摘要，仅供展示与排障。 */
    @Column(name = "fail_reason", length = 200)
    private String failReason;

    /** 乐观锁版本号。 */
    @Version
    @Column(name = "version", nullable = false)
    private long version;

    /** 创建时间。 */
    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    /** 更新时间。 */
    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    @PrePersist
    void fillOnCreate() {
        if (id == null) {
            id = UUID.randomUUID();
        }
        if (createdAt == null) {
            createdAt = Instant.now();
        }
        if (updatedAt == null) {
            updatedAt = createdAt;
        }
        if (status == null) {
            status = BackdropAssetStatus.PROCESSING;
        }
    }

    @PreUpdate
    void fillOnUpdate() {
        updatedAt = Instant.now();
    }
}
