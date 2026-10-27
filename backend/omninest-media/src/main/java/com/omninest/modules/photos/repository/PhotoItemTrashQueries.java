package com.omninest.modules.photos.repository;

import com.omninest.modules.photos.domain.PhotoItem;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.NoRepositoryBean;
import org.springframework.data.repository.query.Param;

/**
 * 照片仓储查询片段；由 {@link PhotoItemRepository} 组合后对外暴露。
 *
 * @author OmniNest
 */
@NoRepositoryBean
public interface PhotoItemTrashQueries {

    // ─── 回收站 ───

    /**
     * 分页查询用户回收站照片的轻量列表投影。
     *
     * @param ownerUserId 用户标识
     * @param pageable 分页和排序参数
     * @return 回收站照片投影分页
     */
    @Query(value = """
            SELECT p.id AS id,
                   p.ownerUserId AS ownerUserId,
                   p.fileNodeId AS fileNodeId,
                   p.title AS title,
                   p.description AS description,
                   p.width AS width,
                   p.height AS height,
                   p.orientation AS orientation,
                   p.dateTaken AS dateTaken,
                   p.gpsLatitude AS gpsLatitude,
                   p.gpsLongitude AS gpsLongitude,
                   p.format AS format,
                   p.fileSize AS fileSize,
                   p.coverFileId AS coverFileId,
                   p.metadataStatus AS metadataStatus,
                   p.motionState AS motionState,
                   p.createdAt AS createdAt
              FROM PhotoItem p
              JOIN FileNode file ON p.fileNodeId = file.id
             WHERE p.ownerUserId = :ownerUserId
               AND p.deletedAt IS NOT NULL
               AND file.deleted = false
             ORDER BY p.deletedAt DESC
            """,
            countQuery = """
                    SELECT COUNT(p)
                      FROM PhotoItem p
                      JOIN FileNode file ON p.fileNodeId = file.id
                     WHERE p.ownerUserId = :ownerUserId
                       AND p.deletedAt IS NOT NULL
                       AND file.deleted = false
                    """)
    Page<PhotoListItemProjection> findTrashPage(
            @Param("ownerUserId") UUID ownerUserId,
            Pageable pageable);

    /**
     * 按用户和 ID 查询回收站中的照片。
     *
     * @param ownerUserId 用户标识
     * @param id 照片标识
     * @return 回收站中的照片
     */
    @Query("""
            SELECT photo FROM PhotoItem photo
            JOIN FileNode file ON photo.fileNodeId = file.id
            WHERE photo.ownerUserId = :ownerUserId AND photo.id = :id
              AND photo.deletedAt IS NOT NULL AND file.deleted = false
            """)
    Optional<PhotoItem> findTrashedByOwnerUserIdAndId(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("id") UUID id
    );

    /**
     * 统计用户回收站中的照片数量。
     *
     * @param ownerUserId 用户标识
     * @return 回收站照片数量
     */
    long countByOwnerUserIdAndDeletedAtIsNotNull(UUID ownerUserId);

    /**
     * 分页查询用户回收站中进入时间早于截止时间的照片，供清空与过期清理。
     *
     * <p>必须带上限读取：清空回收站曾一次性拉取全部照片并塞进单个删除任务，
     * 大回收站会同时撑爆任务载荷与单事务行数。</p>
     *
     * @param ownerUserId 用户标识
     * @param cutoff 截止时间
     * @param pageable 批次上限
     * @return 回收站照片
     */
    @Query("""
            SELECT photo FROM PhotoItem photo
            JOIN FileNode file ON photo.fileNodeId = file.id
            WHERE photo.ownerUserId = :ownerUserId
              AND photo.deletedAt IS NOT NULL
              AND photo.deletedAt <= :cutoff
              AND file.deleted = false
            ORDER BY photo.deletedAt ASC
            """)
    List<PhotoItem> findTrashBatch(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("cutoff") Instant cutoff,
            Pageable pageable
    );


    /**
     * 按 (created_at, id) keyset 游标查询有 GPS 坐标但缺少城市地名的照片。
     *
     * <p>使用 jsonb_exists 避免 JSONB ? 操作符与 JDBC 占位符冲突；
     * 显式列出字段，不使用 SELECT *。</p>
     *
     * @param afterCreatedAt 游标创建时间，首传 null
     * @param afterId 游标照片 ID，首传 null
     * @param limit 返回上限
     * @return 候选照片行
     */
    @Query(value = """
            SELECT p.id, p.gps_latitude, p.gps_longitude, p.created_at
              FROM omni.photo_items p
             WHERE p.gps_latitude IS NOT NULL
               AND p.gps_longitude IS NOT NULL
               AND p.deleted_at IS NULL
               AND (p.gps_location IS NULL OR NOT jsonb_exists(p.gps_location, 'city'))
               AND (:afterCreatedAt::timestamptz IS NULL
                    OR p.created_at > :afterCreatedAt::timestamptz
                    OR (p.created_at = :afterCreatedAt::timestamptz AND p.id > :afterId::uuid))
             ORDER BY p.created_at ASC, p.id ASC
             LIMIT :limit
            """, nativeQuery = true)
    List<GeocodeBackfillRow> findGeocodeBackfillBatch(
            @Param("afterCreatedAt") Instant afterCreatedAt,
            @Param("afterId") UUID afterId,
            @Param("limit") int limit);

    /**
     * 统计有 GPS 坐标但缺少城市地名的照片总数（回填进度估算用）。
     *
     * @return 候选总数
     */
    @Query(value = """
            SELECT COUNT(*)
              FROM omni.photo_items p
             WHERE p.gps_latitude IS NOT NULL
               AND p.gps_longitude IS NOT NULL
               AND p.deleted_at IS NULL
               AND (p.gps_location IS NULL OR NOT jsonb_exists(p.gps_location, 'city'))
            """, nativeQuery = true)
    long countGeocodeBackfillRows();

    /**
     * 条件更新单张照片的位置地名：仅当照片仍无 city 时写入，保证不覆盖已有地点。
     *
     * @param photoId 照片 ID
     * @param gpsLocation 位置地名 JSON
     * @param updatedAt 更新时间
     * @return 实际更新行数（0 表示期间已被其他写入填充或照片已删除）
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query(value = """
            UPDATE omni.photo_items
               SET gps_location = CAST(:gpsLocation AS jsonb),
                   updated_at = :updatedAt,
                   version = version + 1
             WHERE id = :photoId
               AND deleted_at IS NULL
               AND (gps_location IS NULL OR NOT jsonb_exists(gps_location, 'city'))
            """, nativeQuery = true)
    int updateGeocodeLocationIfAbsent(
            @Param("photoId") UUID photoId,
            @Param("gpsLocation") String gpsLocation,
            @Param("updatedAt") Instant updatedAt);

    /**
     * 查询存在过期回收站照片的用户标识。
     *
     * @param cutoff 截止时间
     * @return 用户标识列表
     */
    @Query("""
            SELECT photo.ownerUserId FROM PhotoItem photo
            WHERE photo.deletedAt IS NOT NULL AND photo.deletedAt <= :cutoff
            GROUP BY photo.ownerUserId
            """)
    List<UUID> findOwnerIdsWithExpiredTrash(@Param("cutoff") Instant cutoff);
}
