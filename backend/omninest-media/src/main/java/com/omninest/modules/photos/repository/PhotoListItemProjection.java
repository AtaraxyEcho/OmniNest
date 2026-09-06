package com.omninest.modules.photos.repository;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.Map;
import java.util.UUID;

/**
 * 照片列表查询使用的轻量投影，不加载详情页专用 JSONB 字段。
 *
 * @author OmniNest
 */
public interface PhotoListItemProjection {

    /** @return 照片标识 */
    UUID getId();

    /** @return 所属用户标识 */
    UUID getOwnerUserId();

    /** @return 文件节点标识 */
    UUID getFileNodeId();

    /** @return 照片标题 */
    String getTitle();

    /** @return 照片描述 */
    String getDescription();

    /** @return 图片宽度 */
    Integer getWidth();

    /** @return 图片高度 */
    Integer getHeight();

    /** @return 图片方向 */
    Integer getOrientation();

    /** @return 拍摄时间 */
    Instant getDateTaken();

    /** @return GPS 纬度 */
    BigDecimal getGpsLatitude();

    /** @return GPS 经度 */
    BigDecimal getGpsLongitude();

    /** @return 逆地理地名信息（含中英双语字段），未解析时为空 */
    Map<String, Object> getGpsLocation();

    /** @return 文件格式 */
    String getFormat();

    /** @return 文件字节数 */
    long getFileSize();

    /** @return 封面文件标识 */
    UUID getCoverFileId();

    /** @return 元数据处理状态 */
    String getMetadataStatus();

    /** @return 动态照片状态；NULL 表示历史照片或非动态照片 */
    String getMotionState();

    /** @return 创建时间 */
    Instant getCreatedAt();
}
