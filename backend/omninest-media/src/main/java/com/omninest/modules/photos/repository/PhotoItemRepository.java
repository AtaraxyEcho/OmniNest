package com.omninest.modules.photos.repository;

import com.omninest.modules.photos.domain.PhotoItem;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/**
 * 照片条目仓储接口。
 *
 * @author OmniNest
 */
public interface PhotoItemRepository extends JpaRepository<PhotoItem, UUID> {

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
                   p.createdAt AS createdAt
              FROM PhotoItem p
              JOIN FileNode file ON p.fileNodeId = file.id
             WHERE p.ownerUserId = :ownerUserId
               AND file.deleted = false
               AND p.deletedAt IS NULL
               AND (LOWER(p.title) LIKE LOWER(CONCAT('%', :query, '%'))
                    OR LOWER(COALESCE(p.description, '')) LIKE LOWER(CONCAT('%', :query, '%')))
            """,
            countQuery = """
                    SELECT COUNT(p)
                      FROM PhotoItem p
                      JOIN FileNode file ON p.fileNodeId = file.id
                     WHERE p.ownerUserId = :ownerUserId
                       AND file.deleted = false
                       AND p.deletedAt IS NULL
                       AND (LOWER(p.title) LIKE LOWER(CONCAT('%', :query, '%'))
                            OR LOWER(COALESCE(p.description, '')) LIKE LOWER(CONCAT('%', :query, '%')))
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
                   p.createdAt AS createdAt
              FROM PhotoItem p, PhotoFavorite f, FileNode file
             WHERE p.ownerUserId = :ownerUserId
               AND f.ownerUserId = :ownerUserId
               AND f.photoId = p.id
               AND file.id = p.fileNodeId
               AND file.deleted = false
               AND p.deletedAt IS NULL
               AND (LOWER(p.title) LIKE LOWER(CONCAT('%', :query, '%'))
                    OR LOWER(COALESCE(p.description, '')) LIKE LOWER(CONCAT('%', :query, '%')))
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
                       AND (LOWER(p.title) LIKE LOWER(CONCAT('%', :query, '%'))
                            OR LOWER(COALESCE(p.description, '')) LIKE LOWER(CONCAT('%', :query, '%')))
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
     * 按月份分页查询时间线，并为每个月返回最多四张预览照片。
     *
     * @param ownerUserId 用户标识
     * @param zoneId 时间分组使用的时区
     * @param groupOffset 月份分组偏移量
     * @param groupLimit 月份分组数量上限
     * @return 时间线预览投影
     */
    @Query(value = """
            WITH month_page AS (
                SELECT DATE_TRUNC('month', COALESCE(p.date_taken, p.created_at) AT TIME ZONE :zoneId) AS month_start,
                       COUNT(*) AS photo_count
                  FROM omni.photo_items p
                  JOIN omni.file_nodes f ON f.id = p.file_node_id
                 WHERE p.owner_user_id = :ownerUserId
                   AND f.is_deleted = false
                   AND p.deleted_at IS NULL
                 GROUP BY month_start
                 ORDER BY month_start DESC
                 OFFSET :groupOffset
                 LIMIT :groupLimit
            ), ranked AS (
                SELECT EXTRACT(YEAR FROM mp.month_start)::int AS year,
                       EXTRACT(MONTH FROM mp.month_start)::int AS month,
                       mp.photo_count AS photo_count,
                       p.id,
                       p.owner_user_id,
                       p.file_node_id,
                       p.title,
                       p.description,
                       p.width,
                       p.height,
                       p.orientation,
                       p.date_taken,
                       p.gps_latitude,
                       p.gps_longitude,
                       p.format,
                       p.file_size,
                       p.cover_file_id,
                       p.metadata_status,
                       p.created_at,
                       ROW_NUMBER() OVER (
                           PARTITION BY mp.month_start
                           ORDER BY COALESCE(p.date_taken, p.created_at) DESC, p.id ASC
                       ) AS preview_rank
                  FROM omni.photo_items p
                  JOIN omni.file_nodes f ON f.id = p.file_node_id
                  JOIN month_page mp
                    ON DATE_TRUNC('month', COALESCE(p.date_taken, p.created_at) AT TIME ZONE :zoneId) = mp.month_start
                 WHERE p.owner_user_id = :ownerUserId
                   AND f.is_deleted = false
                   AND p.deleted_at IS NULL
                   AND p.date_taken IS NOT NULL
            )
            SELECT r.year AS "year",
                   r.month AS "month",
                   r.photo_count AS "photoCount",
                   r.id AS "id",
                   r.owner_user_id AS "ownerUserId",
                   r.file_node_id AS "fileNodeId",
                   r.title AS "title",
                   r.description AS "description",
                   r.width AS "width",
                   r.height AS "height",
                   r.orientation AS "orientation",
                   r.date_taken AS "dateTaken",
                   r.gps_latitude AS "gpsLatitude",
                   r.gps_longitude AS "gpsLongitude",
                   r.format AS "format",
                   r.file_size AS "fileSize",
                   r.cover_file_id AS "coverFileId",
                   r.metadata_status AS "metadataStatus",
                   r.created_at AS "createdAt"
              FROM ranked r
             WHERE r.preview_rank <= 4
             ORDER BY r.year DESC, r.month DESC, r.date_taken DESC, r.id ASC
            """, nativeQuery = true)
    List<PhotoTimelinePreviewProjection> findTimelinePreviewPage(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("zoneId") String zoneId,
            @Param("groupOffset") long groupOffset,
            @Param("groupLimit") int groupLimit);

    /**
     * 统计用户照片时间线包含的月份数量。
     *
     * @param ownerUserId 用户标识
     * @param zoneId 时间分组使用的时区
     * @return 月份分组总数
     */
    @Query(value = """
            SELECT COUNT(*)
              FROM (
                  SELECT DATE_TRUNC('month', p.date_taken AT TIME ZONE :zoneId) AS month_start
                    FROM omni.photo_items p
                    JOIN omni.file_nodes f ON f.id = p.file_node_id
                   WHERE p.owner_user_id = :ownerUserId
                     AND f.is_deleted = false
                     AND p.deleted_at IS NULL
                   GROUP BY month_start
              ) timeline_months
            """, nativeQuery = true)
    long countTimelineMonths(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("zoneId") String zoneId);

    /**
     * 按指定维度分页查询照片分组，并为每组返回最多四张预览照片。
     *
     * @param ownerUserId 用户标识
     * @param groupBy 分组维度
     * @param zoneId 日期分组使用的时区
     * @param groupOffset 分组偏移量
     * @param groupLimit 分组数量上限
     * @return 分组预览投影
     */
    @Query(value = """
            WITH grouped_photos AS (
                SELECT CASE
                           WHEN :groupBy = 'DATE'
                               THEN TO_CHAR(p.date_taken AT TIME ZONE :zoneId, 'YYYY-MM')
                           WHEN :groupBy = 'LOCATION'
                               THEN COALESCE(NULLIF(p.gps_location ->> 'city', ''), '未知位置')
                           WHEN :groupBy = 'FORMAT'
                               THEN COALESCE(NULLIF(p.format, ''), '未知')
                           WHEN :groupBy = 'TAG'
                               THEN t.tag
                       END AS group_key,
                       p.id,
                       p.owner_user_id,
                       p.file_node_id,
                       p.title,
                       p.description,
                       p.width,
                       p.height,
                       p.orientation,
                       p.date_taken,
                       p.gps_latitude,
                       p.gps_longitude,
                       p.format,
                       p.file_size,
                       p.cover_file_id,
                       p.metadata_status,
                       p.created_at
                  FROM omni.photo_items p
                  JOIN omni.file_nodes f ON f.id = p.file_node_id
                  LEFT JOIN omni.photo_tags t
                    ON :groupBy = 'TAG'
                   AND t.owner_user_id = :ownerUserId
                   AND t.photo_id = p.id
                 WHERE p.owner_user_id = :ownerUserId
                   AND f.is_deleted = false
                   AND p.deleted_at IS NULL
                   AND (:groupBy <> 'TAG' OR t.id IS NOT NULL)
                   AND (:groupBy <> 'DATE' OR p.date_taken IS NOT NULL)
            ), group_page AS (
                SELECT gp.group_key,
                       COUNT(*) AS photo_count
                  FROM grouped_photos gp
                 WHERE gp.group_key IS NOT NULL
                 GROUP BY gp.group_key
                 ORDER BY gp.group_key ASC
                 OFFSET :groupOffset
                 LIMIT :groupLimit
            ), ranked AS (
                SELECT gp.*,
                       page.photo_count,
                       ROW_NUMBER() OVER (
                           PARTITION BY gp.group_key
                           ORDER BY gp.created_at DESC, gp.id ASC
                       ) AS preview_rank
                  FROM grouped_photos gp
                  JOIN group_page page ON page.group_key = gp.group_key
            )
            SELECT r.group_key AS "groupKey",
                   r.photo_count AS "photoCount",
                   r.id AS "id",
                   r.owner_user_id AS "ownerUserId",
                   r.file_node_id AS "fileNodeId",
                   r.title AS "title",
                   r.description AS "description",
                   r.width AS "width",
                   r.height AS "height",
                   r.orientation AS "orientation",
                   r.date_taken AS "dateTaken",
                   r.gps_latitude AS "gpsLatitude",
                   r.gps_longitude AS "gpsLongitude",
                   r.format AS "format",
                   r.file_size AS "fileSize",
                   r.cover_file_id AS "coverFileId",
                   r.metadata_status AS "metadataStatus",
                   r.created_at AS "createdAt"
              FROM ranked r
             WHERE r.preview_rank <= 4
             ORDER BY r.group_key ASC, r.created_at DESC, r.id ASC
            """, nativeQuery = true)
    List<PhotoGroupPreviewProjection> findGroupPreviewPage(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("groupBy") String groupBy,
            @Param("zoneId") String zoneId,
            @Param("groupOffset") long groupOffset,
            @Param("groupLimit") int groupLimit);

    /**
     * 统计指定维度下的照片分组数量。
     *
     * @param ownerUserId 用户标识
     * @param groupBy 分组维度
     * @param zoneId 日期分组使用的时区
     * @return 分组总数
     */
    @Query(value = """
            SELECT COUNT(DISTINCT CASE
                       WHEN :groupBy = 'DATE'
                           THEN TO_CHAR(p.date_taken AT TIME ZONE :zoneId, 'YYYY-MM')
                       WHEN :groupBy = 'LOCATION'
                           THEN COALESCE(NULLIF(p.gps_location ->> 'city', ''), '未知位置')
                       WHEN :groupBy = 'FORMAT'
                           THEN COALESCE(NULLIF(p.format, ''), '未知')
                       WHEN :groupBy = 'TAG'
                           THEN t.tag
                   END)
              FROM omni.photo_items p
              JOIN omni.file_nodes f ON f.id = p.file_node_id
              LEFT JOIN omni.photo_tags t
                ON :groupBy = 'TAG'
               AND t.owner_user_id = :ownerUserId
               AND t.photo_id = p.id
             WHERE p.owner_user_id = :ownerUserId
               AND f.is_deleted = false
               AND p.deleted_at IS NULL
               AND (:groupBy <> 'TAG' OR t.id IS NOT NULL)
               AND (:groupBy <> 'DATE' OR p.date_taken IS NOT NULL)
            """, nativeQuery = true)
    long countPhotoGroups(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("groupBy") String groupBy,
            @Param("zoneId") String zoneId);

    /**
     * 按用户查询照片列表，按创建时间倒序
     */
    @Query("""
            SELECT photo FROM PhotoItem photo
            JOIN FileNode file ON photo.fileNodeId = file.id
            WHERE photo.ownerUserId = :ownerUserId AND file.deleted = false
              AND photo.deletedAt IS NULL
            ORDER BY photo.createdAt DESC
            """)
    List<PhotoItem> findByOwnerUserIdOrderByCreatedAtDesc(@Param("ownerUserId") UUID ownerUserId);

    /**
     * 按用户和ID查询单张照片
     */
    @Query("""
            SELECT photo FROM PhotoItem photo
            JOIN FileNode file ON photo.fileNodeId = file.id
            WHERE photo.ownerUserId = :ownerUserId AND photo.id = :id AND file.deleted = false
              AND photo.deletedAt IS NULL
            """)
    Optional<PhotoItem> findByOwnerUserIdAndId(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("id") UUID id
    );

    /**
     * 批量查询用户拥有的活动照片。
     *
     * @param ownerUserId 用户标识
     * @param ids 照片标识
     * @return 活动照片
     */
    @Query("""
            SELECT photo FROM PhotoItem photo
            JOIN FileNode file ON photo.fileNodeId = file.id
            WHERE photo.ownerUserId = :ownerUserId AND photo.id IN :ids AND file.deleted = false
              AND photo.deletedAt IS NULL
            """)
    List<PhotoItem> findActiveByOwnerUserIdAndIdIn(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("ids") Collection<UUID> ids
    );

    /**
     * 按用户和文件节点ID查询照片
     */
    Optional<PhotoItem> findByOwnerUserIdAndFileNodeId(UUID ownerUserId, UUID fileNodeId);

    /**
     * 查询用户所有照片的文件节点ID列表
     */
    @Query("""
            SELECT p.fileNodeId FROM PhotoItem p
            JOIN FileNode file ON p.fileNodeId = file.id
            WHERE p.ownerUserId = :ownerUserId AND file.deleted = false
            """)
    List<UUID> findFileNodeIdsByOwnerUserId(@Param("ownerUserId") UUID ownerUserId);

    /**
     * 按用户和文件节点ID批量查询照片
     */
    List<PhotoItem> findByOwnerUserIdAndFileNodeIdIn(UUID ownerUserId, List<UUID> fileNodeIds);

    /**
     * 按文件节点批量查询全部照片。
     *
     * @param fileNodeIds 文件节点 ID
     * @return 照片
     */
    List<PhotoItem> findByFileNodeIdIn(Collection<UUID> fileNodeIds);

    /**
     * 按用户和封面文件ID批量查询照片
     */
    List<PhotoItem> findByOwnerUserIdAndCoverFileIdIn(UUID ownerUserId, Collection<UUID> coverFileIds);

    /**
     * 按封面文件批量查询全部照片。
     *
     * @param coverFileIds 封面文件节点 ID
     * @return 照片
     */
    List<PhotoItem> findByCoverFileIdIn(Collection<UUID> coverFileIds);

    /**
     * 统计用户照片数量
     */
    @Query("""
            SELECT COUNT(photo) FROM PhotoItem photo
            JOIN FileNode file ON photo.fileNodeId = file.id
            WHERE photo.ownerUserId = :ownerUserId AND file.deleted = false
              AND photo.deletedAt IS NULL
            """)
    long countByOwnerUserId(@Param("ownerUserId") UUID ownerUserId);

    /**
     * 分页查询用户照片标识，供长时间批处理控制单批内存占用。
     *
     * @param ownerUserId 用户标识
     * @param pageable 分页参数
     * @return 照片标识分页
     */
    @Query("""
            SELECT p.id FROM PhotoItem p
            JOIN FileNode file ON p.fileNodeId = file.id
            WHERE p.ownerUserId = :ownerUserId AND file.deleted = false
              AND p.deletedAt IS NULL
            """)
    Page<UUID> findIdsByOwnerUserId(
            @Param("ownerUserId") UUID ownerUserId,
            Pageable pageable
    );

    /**
     * 查询用户近期拍摄的照片（按拍摄时间倒序）
     */
    @Query("""
            SELECT p FROM PhotoItem p
            JOIN FileNode file ON p.fileNodeId = file.id
            WHERE p.ownerUserId = :ownerUserId AND file.deleted = false
              AND p.deletedAt IS NULL
              AND p.dateTaken IS NOT NULL
            ORDER BY p.dateTaken DESC
            """)
    List<PhotoItem> findRecentByOwnerUserId(@Param("ownerUserId") UUID ownerUserId);

    /**
     * 按关键词搜索用户照片标题（SQL LIKE 模糊匹配）。
     * 作为 Lucene 全文索引的降级回退，由 PhotoLibraryService.searchPhotos 在索引无结果时调用。
     */
    @Query("""
            SELECT p FROM PhotoItem p
            JOIN FileNode file ON p.fileNodeId = file.id
            WHERE p.ownerUserId = :ownerUserId AND file.deleted = false
              AND p.deletedAt IS NULL
              AND LOWER(p.title) LIKE LOWER(CONCAT('%', :keyword, '%'))
            """)
    List<PhotoItem> searchByOwnerUserIdAndKeyword(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("keyword") String keyword);

    /**
     * 按拍摄时间范围查询用户照片
     */
    @Query("""
            SELECT p FROM PhotoItem p
            JOIN FileNode file ON p.fileNodeId = file.id
            WHERE p.ownerUserId = :ownerUserId AND file.deleted = false
              AND p.deletedAt IS NULL
              AND p.dateTaken >= :from AND p.dateTaken < :to
            ORDER BY p.dateTaken DESC
            """)
    List<PhotoItem> findByOwnerUserIdAndDateTakenBetween(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("from") Instant from,
            @Param("to") Instant to);

    /**
     * 查询用户最新的N张照片
     */
    @Query("""
            SELECT p FROM PhotoItem p
            JOIN FileNode file ON p.fileNodeId = file.id
            WHERE p.ownerUserId = :ownerUserId AND file.deleted = false
              AND p.deletedAt IS NULL
            ORDER BY p.createdAt DESC
            LIMIT :limit
            """)
    List<PhotoItem> findTopNByOwnerUserIdOrderByCreatedAtDesc(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("limit") int limit);

    /**
     * 查询用户照片中 providerMetadata.contentHash 匹配指定哈希值的照片，
     * 返回已存在的 contentHash 列表。
     */
    @Query(value = "SELECT DISTINCT (p.provider_metadata->>'contentHash')::text FROM omni.photo_items p "
            + "WHERE p.owner_user_id = :ownerUserId "
            + "AND p.provider_metadata->>'contentHash' IS NOT NULL "
            + "AND (p.provider_metadata->>'contentHash')::text IN (:hashes)",
            nativeQuery = true)
    List<String> findExistingContentHashes(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("hashes") List<String> hashes);

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
     * 查询用户回收站中进入时间早于截止时间的照片，供清空与过期清理。
     *
     * @param ownerUserId 用户标识
     * @param cutoff 截止时间
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
    List<PhotoItem> findTrashByOwnerUserIdAndDeletedAtBefore(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("cutoff") Instant cutoff
    );

    /**
     * 回填候选投影：仅取游标推进与逆地理编码所需字段。
     */
    interface GeocodeBackfillRow {
        UUID getId();

        BigDecimal getGpsLatitude();

        BigDecimal getGpsLongitude();

        Instant getCreatedAt();
    }

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

    // ─── 关系图谱边聚合 ───

    @Query(value = """
            SELECT e.source_key AS "sourceKey",
                   e.target_key AS "targetKey",
                   e.weight AS "weight"
              FROM (
                    SELECT a1.album_id AS source_key,
                           a2.album_id AS target_key,
                           COUNT(*) AS weight
                      FROM omni.photo_album_items a1
                      JOIN omni.photo_album_items a2
                        ON a2.photo_id = a1.photo_id AND a2.owner_user_id = a1.owner_user_id
                     WHERE a1.owner_user_id = :ownerUserId
                       AND a2.album_id > a1.album_id
                     GROUP BY 1, 2
                   ) e
             ORDER BY e.weight DESC, e.source_key ASC, e.target_key ASC
             LIMIT :limit
            """, nativeQuery = true)
    List<PhotoRelationEdgeProjection> findAlbumAlbumRelationEdges(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("limit") int limit);

    @Query(value = """
            SELECT e.source_key AS "sourceKey",
                   e.target_key AS "targetKey",
                   e.weight AS "weight"
              FROM (
                    SELECT ai.album_id AS source_key,
                           f.cluster_id AS target_key,
                           COUNT(DISTINCT f.photo_id) AS weight
                      FROM omni.photo_faces f
                      JOIN omni.photo_album_items ai
                        ON ai.photo_id = f.photo_id AND ai.owner_user_id = f.owner_user_id
                     WHERE f.owner_user_id = :ownerUserId
                       AND f.cluster_id IS NOT NULL
                     GROUP BY 1, 2
                   ) e
             ORDER BY e.weight DESC, e.source_key ASC, e.target_key ASC
             LIMIT :limit
            """, nativeQuery = true)
    List<PhotoRelationEdgeProjection> findAlbumPersonRelationEdges(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("limit") int limit);

    @Query(value = """
            SELECT e.source_key AS "sourceKey",
                   e.target_key AS "targetKey",
                   e.weight AS "weight"
              FROM (
                    SELECT ai.album_id AS source_key,
                           TO_CHAR(p.date_taken AT TIME ZONE :zoneId, 'YYYY-MM') AS target_key,
                           COUNT(*) AS weight
                      FROM omni.photo_album_items ai
                      JOIN omni.photo_items p
                        ON p.id = ai.photo_id AND p.owner_user_id = ai.owner_user_id
                     WHERE ai.owner_user_id = :ownerUserId
                       AND p.date_taken IS NOT NULL
                     GROUP BY 1, 2
                   ) e
             ORDER BY e.weight DESC, e.source_key ASC, e.target_key ASC
             LIMIT :limit
            """, nativeQuery = true)
    List<PhotoRelationEdgeProjection> findAlbumTimeRelationEdges(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("zoneId") String zoneId,
            @Param("limit") int limit);

    @Query(value = """
            SELECT e.source_key AS "sourceKey",
                   e.target_key AS "targetKey",
                   e.weight AS "weight"
              FROM (
                    SELECT ai.album_id AS source_key,
                           COALESCE(NULLIF(p.gps_location ->> 'city', ''), '未知位置') AS target_key,
                           COUNT(*) AS weight
                      FROM omni.photo_album_items ai
                      JOIN omni.photo_items p
                        ON p.id = ai.photo_id AND p.owner_user_id = ai.owner_user_id
                     WHERE ai.owner_user_id = :ownerUserId
                     GROUP BY 1, 2
                   ) e
             ORDER BY e.weight DESC, e.source_key ASC, e.target_key ASC
             LIMIT :limit
            """, nativeQuery = true)
    List<PhotoRelationEdgeProjection> findAlbumLocationRelationEdges(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("limit") int limit);

    @Query(value = """
            SELECT e.source_key AS "sourceKey",
                   e.target_key AS "targetKey",
                   e.weight AS "weight"
              FROM (
                    SELECT f.cluster_id AS source_key,
                           TO_CHAR(p.date_taken AT TIME ZONE :zoneId, 'YYYY-MM') AS target_key,
                           COUNT(*) AS weight
                      FROM omni.photo_faces f
                      JOIN omni.photo_items p
                        ON p.id = f.photo_id AND p.owner_user_id = f.owner_user_id
                     WHERE f.owner_user_id = :ownerUserId
                       AND f.cluster_id IS NOT NULL
                       AND p.date_taken IS NOT NULL
                     GROUP BY 1, 2
                   ) e
             ORDER BY e.weight DESC, e.source_key ASC, e.target_key ASC
             LIMIT :limit
            """, nativeQuery = true)
    List<PhotoRelationEdgeProjection> findPersonTimeRelationEdges(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("zoneId") String zoneId,
            @Param("limit") int limit);

    @Query(value = """
            SELECT e.source_key AS "sourceKey",
                   e.target_key AS "targetKey",
                   e.weight AS "weight"
              FROM (
                    SELECT f.cluster_id AS source_key,
                           COALESCE(NULLIF(p.gps_location ->> 'city', ''), '未知位置') AS target_key,
                           COUNT(*) AS weight
                      FROM omni.photo_faces f
                      JOIN omni.photo_items p
                        ON p.id = f.photo_id AND p.owner_user_id = f.owner_user_id
                     WHERE f.owner_user_id = :ownerUserId
                       AND f.cluster_id IS NOT NULL
                     GROUP BY 1, 2
                   ) e
             ORDER BY e.weight DESC, e.source_key ASC, e.target_key ASC
             LIMIT :limit
            """, nativeQuery = true)
    List<PhotoRelationEdgeProjection> findPersonLocationRelationEdges(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("limit") int limit);

    @Query(value = """
            SELECT e.source_key AS "sourceKey",
                   e.target_key AS "targetKey",
                   e.weight AS "weight"
              FROM (
                    SELECT TO_CHAR(p.date_taken AT TIME ZONE :zoneId, 'YYYY-MM') AS source_key,
                           COALESCE(NULLIF(p.gps_location ->> 'city', ''), '未知位置') AS target_key,
                           COUNT(*) AS weight
                      FROM omni.photo_items p
                     WHERE p.owner_user_id = :ownerUserId
                       AND p.date_taken IS NOT NULL
                     GROUP BY 1, 2
                   ) e
             ORDER BY e.weight DESC, e.source_key ASC, e.target_key ASC
             LIMIT :limit
            """, nativeQuery = true)
    List<PhotoRelationEdgeProjection> findTimeLocationRelationEdges(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("zoneId") String zoneId,
            @Param("limit") int limit);

    @Query(value = """
            SELECT a.id AS "key",
                   a.name AS "label",
                   a.photo_count AS "weight"
              FROM omni.photo_albums a
             WHERE a.owner_user_id = :ownerUserId
             ORDER BY a.photo_count DESC, a.name ASC
             LIMIT :limit
            """, nativeQuery = true)
    List<PhotoRelationNodeProjection> findAlbumRelationNodes(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("limit") int limit);

    @Query(value = """
            SELECT c.id AS "key",
                   c.name AS "label",
                   c.face_count AS "weight"
              FROM omni.photo_face_clusters c
             WHERE c.owner_user_id = :ownerUserId
             ORDER BY c.face_count DESC, c.id ASC
             LIMIT :limit
            """, nativeQuery = true)
    List<PhotoRelationNodeProjection> findPersonRelationNodes(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("limit") int limit);

    @Query(value = """
            SELECT TO_CHAR(p.date_taken AT TIME ZONE :zoneId, 'YYYY-MM') AS "key",
                   CAST(NULL AS varchar) AS "label",
                   COUNT(*) AS "weight"
              FROM omni.photo_items p
             WHERE p.owner_user_id = :ownerUserId
               AND p.date_taken IS NOT NULL
             GROUP BY 1
             ORDER BY 1 ASC
             LIMIT :limit
            """, nativeQuery = true)
    List<PhotoRelationNodeProjection> findTimeRelationNodes(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("zoneId") String zoneId,
            @Param("limit") int limit);

    @Query(value = """
            SELECT COALESCE(NULLIF(p.gps_location ->> 'city', ''), '未知位置') AS "key",
                   CAST(NULL AS varchar) AS "label",
                   COUNT(*) AS "weight"
              FROM omni.photo_items p
             WHERE p.owner_user_id = :ownerUserId
             GROUP BY 1
             ORDER BY 3 DESC, 1 ASC
             LIMIT :limit
            """, nativeQuery = true)
    List<PhotoRelationNodeProjection> findLocationRelationNodes(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("limit") int limit);

    @Query("""
            SELECT p.id
              FROM PhotoItem p
             WHERE p.ownerUserId = :ownerUserId
               AND p.coverFileId IS NULL
             ORDER BY p.createdAt DESC
            """)
    List<UUID> findIdsMissingCover(@Param("ownerUserId") UUID ownerUserId);
}
