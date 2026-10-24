package com.omninest.modules.photos.repository;

import com.omninest.modules.photos.domain.PhotoItem;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.NoRepositoryBean;
import org.springframework.data.repository.query.Param;

/**
 * 照片仓储查询片段；由 {@link PhotoItemRepository} 组合后对外暴露。
 *
 * @author OmniNest
 */
@NoRepositoryBean
public interface PhotoItemBrowseQueries {

    /**
     * 分页查询用户照片的轻量列表投影。
     *
     * @param ownerUserId 用户标识
     * @param pageable 分页和排序参数
     * @return 照片投影分页
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
                   p.gpsLocation AS gpsLocation,
                   p.format AS format,
                   p.fileSize AS fileSize,
                   p.coverFileId AS coverFileId,
                   p.metadataStatus AS metadataStatus,
                   p.motionState AS motionState,
                   p.createdAt AS createdAt
              FROM PhotoItem p
              JOIN FileNode file ON p.fileNodeId = file.id
             WHERE p.ownerUserId = :ownerUserId
               AND file.deleted = false
               AND p.deletedAt IS NULL
            """,
            countQuery = """
                    SELECT COUNT(p)
                      FROM PhotoItem p
                      JOIN FileNode file ON p.fileNodeId = file.id
                     WHERE p.ownerUserId = :ownerUserId
                       AND file.deleted = false
                       AND p.deletedAt IS NULL
                    """)
    Page<PhotoListItemProjection> findListPage(
            @Param("ownerUserId") UUID ownerUserId,
            Pageable pageable);

    /**
     * 按关键词分页查询用户照片的轻量列表投影。
     *
     * @param ownerUserId 用户标识
     * @param query 标题或描述筛选词
     * @param pageable 分页和排序参数
     * @return 照片投影分页
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
                   p.gpsLocation AS gpsLocation,
                   p.format AS format,
                   p.fileSize AS fileSize,
                   p.coverFileId AS coverFileId,
                   p.metadataStatus AS metadataStatus,
                   p.motionState AS motionState,
                   p.createdAt AS createdAt
              FROM PhotoItem p
              JOIN FileNode file ON p.fileNodeId = file.id
             WHERE p.ownerUserId = :ownerUserId
               AND file.deleted = false
               AND p.deletedAt IS NULL
               AND (LOWER(p.title) LIKE LOWER(CONCAT('%', :query, '%')) ESCAPE '\\'
                    OR LOWER(COALESCE(p.description, '')) LIKE LOWER(CONCAT('%', :query, '%')) ESCAPE '\\')
            """,
            countQuery = """
                    SELECT COUNT(p)
                      FROM PhotoItem p
                      JOIN FileNode file ON p.fileNodeId = file.id
                     WHERE p.ownerUserId = :ownerUserId
                       AND file.deleted = false
                       AND p.deletedAt IS NULL
                       AND (LOWER(p.title) LIKE LOWER(CONCAT('%', :query, '%')) ESCAPE '\\'
                            OR LOWER(COALESCE(p.description, '')) LIKE LOWER(CONCAT('%', :query, '%')) ESCAPE '\\')
                    """)
    Page<PhotoListItemProjection> searchListPage(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("query") String query,
            Pageable pageable);

    /**
     * 分页查询用户收藏照片的轻量列表投影。
     *
     * @param ownerUserId 用户标识
     * @param pageable 分页和排序参数
     * @return 收藏照片投影分页
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
                   p.gpsLocation AS gpsLocation,
                   p.format AS format,
                   p.fileSize AS fileSize,
                   p.coverFileId AS coverFileId,
                   p.metadataStatus AS metadataStatus,
                   p.motionState AS motionState,
                   p.createdAt AS createdAt
              FROM PhotoItem p, PhotoFavorite f, FileNode file
             WHERE p.ownerUserId = :ownerUserId
               AND f.ownerUserId = :ownerUserId
               AND f.photoId = p.id
               AND file.id = p.fileNodeId
               AND file.deleted = false
               AND p.deletedAt IS NULL
            """,
            countQuery = """
                    SELECT COUNT(p)
                      FROM PhotoItem p, PhotoFavorite f, FileNode file
                     WHERE p.ownerUserId = :ownerUserId
                       AND f.ownerUserId = :ownerUserId
                       AND f.photoId = p.id
                       AND file.id = p.fileNodeId
                       AND file.deleted = false
                       AND p.deletedAt IS NULL
                    """)
    Page<PhotoListItemProjection> findFavoriteListPage(
            @Param("ownerUserId") UUID ownerUserId,
            Pageable pageable);

    /**
     * 按关键词分页查询用户收藏照片的轻量列表投影。
     *
     * @param ownerUserId 用户标识
     * @param query 标题或描述筛选词
     * @param pageable 分页和排序参数
     * @return 收藏照片投影分页
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
                   p.gpsLocation AS gpsLocation,
                   p.format AS format,
                   p.fileSize AS fileSize,
                   p.coverFileId AS coverFileId,
                   p.metadataStatus AS metadataStatus,
                   p.motionState AS motionState,
                   p.createdAt AS createdAt
              FROM PhotoItem p, PhotoFavorite f, FileNode file
             WHERE p.ownerUserId = :ownerUserId
               AND f.ownerUserId = :ownerUserId
               AND f.photoId = p.id
               AND file.id = p.fileNodeId
               AND file.deleted = false
               AND p.deletedAt IS NULL
               AND (LOWER(p.title) LIKE LOWER(CONCAT('%', :query, '%')) ESCAPE '\\'
                    OR LOWER(COALESCE(p.description, '')) LIKE LOWER(CONCAT('%', :query, '%')) ESCAPE '\\')
            """,
            countQuery = """
                    SELECT COUNT(p)
                      FROM PhotoItem p, PhotoFavorite f, FileNode file
                     WHERE p.ownerUserId = :ownerUserId
                       AND f.ownerUserId = :ownerUserId
                       AND f.photoId = p.id
                       AND file.id = p.fileNodeId
                       AND file.deleted = false
                       AND p.deletedAt IS NULL
                       AND (LOWER(p.title) LIKE LOWER(CONCAT('%', :query, '%')) ESCAPE '\\'
                            OR LOWER(COALESCE(p.description, '')) LIKE LOWER(CONCAT('%', :query, '%')) ESCAPE '\\')
                    """)
    Page<PhotoListItemProjection> searchFavoriteListPage(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("query") String query,
            Pageable pageable);

    /**
     * 按年月区间分页查询用户照片的轻量列表投影。
     *
     * <p>排序与时间线一致：以拍摄时间缺失时回退创建时间的复合值参与排序，由服务层把年月换算为起止时刻。</p>
     *
     * @param ownerUserId 用户标识
     * @param periodStart 区间起点（含）
     * @param periodEnd 区间终点（不含）
     * @param pageable 分页和排序参数
     * @return 照片投影分页
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
                   p.gpsLocation AS gpsLocation,
                   p.format AS format,
                   p.fileSize AS fileSize,
                   p.coverFileId AS coverFileId,
                   p.metadataStatus AS metadataStatus,
                   p.motionState AS motionState,
                   p.createdAt AS createdAt
              FROM PhotoItem p, FileNode file
             WHERE p.ownerUserId = :ownerUserId
               AND file.id = p.fileNodeId
               AND file.deleted = false
               AND p.deletedAt IS NULL
               AND COALESCE(p.dateTaken, p.createdAt) >= :periodStart
               AND COALESCE(p.dateTaken, p.createdAt) < :periodEnd
            """,
            countQuery = """
                    SELECT COUNT(p)
                      FROM PhotoItem p, FileNode file
                     WHERE p.ownerUserId = :ownerUserId
                       AND file.id = p.fileNodeId
                       AND file.deleted = false
                       AND p.deletedAt IS NULL
                       AND COALESCE(p.dateTaken, p.createdAt) >= :periodStart
                       AND COALESCE(p.dateTaken, p.createdAt) < :periodEnd
                    """)
    Page<PhotoListItemProjection> findPeriodListPage(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("periodStart") Instant periodStart,
            @Param("periodEnd") Instant periodEnd,
            Pageable pageable);

    /**
     * 分页查询可加入相册的候选照片投影，排除已在该相册内的照片。
     *
     * @param ownerUserId 用户标识
     * @param albumId 相册标识
     * @param pageable 分页和排序参数
     * @return 候选照片投影分页
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
                   p.gpsLocation AS gpsLocation,
                   p.format AS format,
                   p.fileSize AS fileSize,
                   p.coverFileId AS coverFileId,
                   p.metadataStatus AS metadataStatus,
                   p.motionState AS motionState,
                   p.createdAt AS createdAt
              FROM PhotoItem p, FileNode file
             WHERE p.ownerUserId = :ownerUserId
               AND file.id = p.fileNodeId
               AND file.deleted = false
               AND p.deletedAt IS NULL
               AND NOT EXISTS (
                   SELECT 1
                     FROM PhotoAlbumItem ai
                    WHERE ai.albumId = :albumId
                      AND ai.photoId = p.id
               )
            """,
            countQuery = """
                    SELECT COUNT(p)
                      FROM PhotoItem p, FileNode file
                     WHERE p.ownerUserId = :ownerUserId
                       AND file.id = p.fileNodeId
                       AND file.deleted = false
                       AND p.deletedAt IS NULL
                       AND NOT EXISTS (
                           SELECT 1
                             FROM PhotoAlbumItem ai
                            WHERE ai.albumId = :albumId
                              AND ai.photoId = p.id
                       )
                    """)
    Page<PhotoListItemProjection> findAlbumCandidatePage(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("albumId") UUID albumId,
            Pageable pageable);

    /**
     * 分页查询动态照片回扫候选：尚无运动状态、可解码 JPEG 且未删除的照片。
     *
     * @param ownerUserId 用户标识
     * @param startAfterId 游标照片 ID，首批传 null
     * @param pageable 分页参数（仅用页大小，按 ID 升序）
     * @return 候选照片列表
     */
    @Query(value = """
            SELECT p
              FROM PhotoItem p
             WHERE p.ownerUserId = :ownerUserId
               AND p.deletedAt IS NULL
               AND p.motionState IS NULL
               AND LOWER(p.format) IN ('jpg', 'jpeg')
               AND (:startAfterId IS NULL OR p.id > :startAfterId)
             ORDER BY p.id ASC
            """)
    List<PhotoItem> findMotionRescanCandidates(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("startAfterId") UUID startAfterId,
            Pageable pageable);

    /**
     * 统计动态照片回扫候选总数，用于任务进度基准。
     *
     * @param ownerUserId 用户标识
     * @return 候选总数
     */
    @Query(value = """
            SELECT COUNT(p)
              FROM PhotoItem p
             WHERE p.ownerUserId = :ownerUserId
               AND p.deletedAt IS NULL
               AND p.motionState IS NULL
               AND LOWER(p.format) IN ('jpg', 'jpeg')
            """)
    long countMotionRescanCandidates(@Param("ownerUserId") UUID ownerUserId);
}
