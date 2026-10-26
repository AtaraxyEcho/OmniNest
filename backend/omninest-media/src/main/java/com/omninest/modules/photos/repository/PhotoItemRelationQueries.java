package com.omninest.modules.photos.repository;

import java.util.Collection;
import java.util.List;
import java.util.UUID;
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
public interface PhotoItemRelationQueries {

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
                       AND EXISTS (
                           SELECT 1
                             FROM omni.photo_items pi
                             JOIN omni.file_nodes fi ON fi.id = pi.file_node_id
                            WHERE pi.id = a1.photo_id
                              AND pi.deleted_at IS NULL
                              AND fi.is_deleted = false
                       )
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
                           TO_CHAR(COALESCE(p.date_taken, p.created_at) AT TIME ZONE :zoneId, 'YYYY-MM') AS target_key,
                           COUNT(*) AS weight
                      FROM omni.photo_album_items ai
                      JOIN omni.photo_items p
                        ON p.id = ai.photo_id AND p.owner_user_id = ai.owner_user_id
                      JOIN omni.file_nodes f ON f.id = p.file_node_id
                     WHERE ai.owner_user_id = :ownerUserId
                       AND f.is_deleted = false
                       AND p.deleted_at IS NULL
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
                      JOIN omni.file_nodes f ON f.id = p.file_node_id
                     WHERE ai.owner_user_id = :ownerUserId
                       AND f.is_deleted = false
                       AND p.deleted_at IS NULL
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
                    SELECT TO_CHAR(COALESCE(p.date_taken, p.created_at) AT TIME ZONE :zoneId, 'YYYY-MM') AS source_key,
                           COALESCE(NULLIF(p.gps_location ->> 'city', ''), '未知位置') AS target_key,
                           COUNT(*) AS weight
                      FROM omni.photo_items p
                      JOIN omni.file_nodes f ON f.id = p.file_node_id
                     WHERE p.owner_user_id = :ownerUserId
                       AND f.is_deleted = false
                       AND p.deleted_at IS NULL
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
            SELECT TO_CHAR(COALESCE(p.date_taken, p.created_at) AT TIME ZONE :zoneId, 'YYYY-MM') AS "key",
                   CAST(NULL AS varchar) AS "label",
                   COUNT(*) AS "weight"
              FROM omni.photo_items p
              JOIN omni.file_nodes f ON f.id = p.file_node_id
             WHERE p.owner_user_id = :ownerUserId
               AND f.is_deleted = false
               AND p.deleted_at IS NULL
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
              JOIN omni.file_nodes f ON f.id = p.file_node_id
             WHERE p.owner_user_id = :ownerUserId
               AND f.is_deleted = false
               AND p.deleted_at IS NULL
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

    /**
     * 批量读取照片当前活动的全分辨率文件节点，只返回已产生编辑产物的照片。
     *
     * <p>列表接口据此把大图地址指向编辑产物；未编辑的照片不在结果中，由调用方回退到
     * {@code fileNodeId} 原图。用单列投影是为了不把整行实体拉进列表装配路径。</p>
     *
     * @param ownerUserId 所属用户 ID
     * @param photoIds 当前页照片 ID
     * @return 已编辑照片的活动文件投影
     */
    @Query("""
            SELECT p.id AS photoId,
                   p.activeFileId AS activeFileId
              FROM PhotoItem p
             WHERE p.ownerUserId = :ownerUserId
               AND p.id IN :photoIds
               AND p.activeFileId IS NOT NULL
            """)
    List<PhotoActiveFileProjection> findActiveFileIds(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("photoIds") Collection<UUID> photoIds);

    /**
     * 按主键游标读取需要重建搜索索引的照片，跨全部用户。
     *
     * <p>仅服务于管理员发起的全站索引重建：索引字段口径变更后旧文档不会再被新查询命中，
     * 只能整卷重投。排除回收站照片与文件已删除的照片，与 {@code findActiveByOwnerUserIdAndIdIn}
     * 同一判据；游标按 ID 推进，与文件索引重建侧保持同一翻页方式。</p>
     *
     * @param afterId 上一页最大照片 ID，首页传最小 UUID
     * @param limit 单批数量
     * @return 按 ID 升序的照片投影批次
     */
    @Query("""
            SELECT p.id AS id,
                   p.ownerUserId AS ownerUserId
              FROM PhotoItem p
              JOIN FileNode file ON p.fileNodeId = file.id
             WHERE file.deleted = false
               AND p.deletedAt IS NULL
               AND p.id > :afterId
             ORDER BY p.id ASC
            """)
    List<PhotoIndexTargetProjection> findIndexablePhotosAfterId(
            @Param("afterId") UUID afterId,
            Pageable limit);

    /**
     * 统计需要重建搜索索引的照片总数，用于换算任务进度。
     *
     * @return 待重投照片数
     */
    @Query("""
            SELECT COUNT(p)
              FROM PhotoItem p
              JOIN FileNode file ON p.fileNodeId = file.id
             WHERE file.deleted = false
               AND p.deletedAt IS NULL
            """)
    long countIndexablePhotos();
}
