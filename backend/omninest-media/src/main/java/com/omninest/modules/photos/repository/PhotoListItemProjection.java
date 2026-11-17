package com.omninest.modules.photos.repository;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.Map;
import java.util.UUID;

/**
 * 照片列表查询使用的轻量投影。
 *
 * <p>不加载详情专用大字段（providerMetadata、EXIF 宽表等）；description 供客户端
 * 本地过滤，gpsLocation 供卡片/幻灯片位置文案，故保留在列表投影中。</p>
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
