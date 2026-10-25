package com.omninest.modules.photos.repository;

import java.util.List;
import java.util.UUID;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.NoRepositoryBean;
import org.springframework.data.repository.query.Param;

/**
 * 照片仓储查询片段；由 {@link PhotoItemRepository} 组合后对外暴露。
 *
 * @author OmniNest
 */
@NoRepositoryBean
public interface PhotoItemTimelineQueries {

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
                       p.motion_state,
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
                   r.motion_state AS "motionState",
                   r.created_at AS "createdAt"
              FROM ranked r
             WHERE r.preview_rank <= 4
             ORDER BY r.year DESC, r.month DESC, COALESCE(r.date_taken, r.created_at) DESC, r.id ASC
            """, nativeQuery = true)
    List<PhotoTimelinePreviewProjection> findTimelinePreviewPage(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("zoneId") String zoneId,
            @Param("groupOffset") long groupOffset,
            @Param("groupLimit") int groupLimit);

    /**
     * 统计用户照片时间线包含的月份数量。
     *
     * <p>月份键必须与 findTimelinePreviewPage 完全一致
     * （COALESCE(date_taken, created_at)），否则无 EXIF 照片会折叠进
     * NULL 月份导致 totalElements 与分页内容双向不一致。</p>
     *
     * @param ownerUserId 用户标识
     * @param zoneId 时间分组使用的时区
     * @return 月份分组总数
     */
    @Query(value = """
            SELECT COUNT(*)
              FROM (
                  SELECT DATE_TRUNC('month', COALESCE(p.date_taken, p.created_at) AT TIME ZONE :zoneId) AS month_start
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
                       p.motion_state,
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
                 ORDER BY CASE WHEN CAST(:groupBy AS text) = 'DATE' THEN gp.group_key END DESC,
                          gp.group_key ASC
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
                   r.motion_state AS "motionState",
                   r.created_at AS "createdAt"
              FROM ranked r
             WHERE r.preview_rank <= 4
             ORDER BY CASE WHEN CAST(:groupBy AS text) = 'DATE' THEN r.group_key END DESC,
                      r.group_key ASC, r.created_at DESC, r.id ASC
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
     * 按地点分组键分页查询照片 ID。
     *
     * <p>地点键与分组聚合使用同一表达式：{@code gps_location.city} 为空时归入
     * “未知位置”。先取 ID 再批量装配实体，避免原生查询投影 jsonb 字段。</p>
     *
     * @param ownerUserId 用户标识
     * @param location 地点分组键
     * @param limit 每页条数
     * @param offset 偏移量
     * @return 照片 ID 列表
     */
    @Query(value = """
            SELECT p.id
              FROM omni.photo_items p
              JOIN omni.file_nodes f ON f.id = p.file_node_id
             WHERE p.owner_user_id = :ownerUserId
               AND f.is_deleted = false
               AND p.deleted_at IS NULL
               AND COALESCE(NULLIF(p.gps_location ->> 'city', ''), '未知位置') = :location
             ORDER BY COALESCE(p.date_taken, p.created_at) DESC, p.id ASC
             LIMIT :limit OFFSET :offset
            """, nativeQuery = true)
    List<UUID> findIdsByLocation(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("location") String location,
            @Param("limit") int limit,
            @Param("offset") long offset);

    /**
     * 统计指定地点分组键下的照片数量。
     *
     * @param ownerUserId 用户标识
     * @param location 地点分组键
     * @return 照片数量
     */
    @Query(value = """
            SELECT COUNT(*)
              FROM omni.photo_items p
              JOIN omni.file_nodes f ON f.id = p.file_node_id
             WHERE p.owner_user_id = :ownerUserId
               AND f.is_deleted = false
               AND p.deleted_at IS NULL
               AND COALESCE(NULLIF(p.gps_location ->> 'city', ''), '未知位置') = :location
            """, nativeQuery = true)
    long countByLocation(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("location") String location);
}
