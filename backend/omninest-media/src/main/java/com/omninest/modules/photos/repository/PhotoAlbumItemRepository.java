package com.omninest.modules.photos.repository;

import com.omninest.modules.photos.domain.PhotoAlbumItem;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/**
 * 相册-照片关联仓储接口
 */
public interface PhotoAlbumItemRepository extends JpaRepository<PhotoAlbumItem, UUID> {

    /**
     * 按用户和相册查询关联条目，按排序序号升序
     */
    List<PhotoAlbumItem> findByOwnerUserIdAndAlbumIdOrderBySortOrderAsc(UUID ownerUserId, UUID albumId);

    /**
     * 按相册和照片查询关联条目
     */
    Optional<PhotoAlbumItem> findByAlbumIdAndPhotoId(UUID albumId, UUID photoId);

    /**
     * 判断相册中是否已包含指定照片
     */
    boolean existsByAlbumIdAndPhotoId(UUID albumId, UUID photoId);

    /**
     * 按相册和照片删除关联条目
     */
    void deleteByAlbumIdAndPhotoId(UUID albumId, UUID photoId);

    /**
     * 查询相册中所有照片ID，按排序序号升序
     */
    @Query("SELECT ai.photoId FROM PhotoAlbumItem ai WHERE ai.albumId = :albumId ORDER BY ai.sortOrder ASC")
    List<UUID> findPhotoIdsByAlbumId(@Param("albumId") UUID albumId);

    /** 分页查询相册照片标识。 */
    @Query("SELECT ai.photoId FROM PhotoAlbumItem ai WHERE ai.albumId = :albumId ORDER BY ai.sortOrder ASC")
    List<UUID> findPhotoIdsByAlbumId(@Param("albumId") UUID albumId, Pageable pageable);

    /**
     * 查询相册内活动照片标识（分页），口径与 {@code countActivePhotosByAlbumId} 相同。
     *
     * <p>相册关联条目在照片移入回收站时不删除（恢复后还要回到原相册），因此必须在查询里
     * 过滤软删除照片：先分页取全部关联再在内存过滤，会让每页实际数量不足 size、
     * 整页为空，总数也会虚高。</p>
     *
     * @param albumId 相册 ID
     * @param pageable 分页参数
     * @return 活动照片标识
     */
    @Query("""
            SELECT ai.photoId
            FROM PhotoAlbumItem ai
            JOIN PhotoItem photo ON photo.id = ai.photoId
            JOIN FileNode file ON photo.fileNodeId = file.id
            WHERE ai.albumId = :albumId
              AND file.deleted = false
              AND photo.deletedAt IS NULL
            ORDER BY ai.sortOrder ASC
            """)
    List<UUID> findActivePhotoIdsByAlbumId(
            @Param("albumId") UUID albumId,
            Pageable pageable
    );

    /**
     * 批量查询多个相册的首张有效照片封面文件。
     *
     * <p>相册列表逐相册回查会按相册数量放大成 N+1；窗口函数一次取回当前页
     * 每个相册排序最靠前且仍可用的封面文件。</p>
     *
     * @param albumIds 相册标识集合
     * @return 相册与其首张封面文件的对应关系
     */
    @Query(value = """
            SELECT ranked.album_id AS "albumId", ranked.cover_file_id AS "coverFileId"
            FROM (
                SELECT ai.album_id,
                       pi.cover_file_id,
                       ROW_NUMBER() OVER (
                           PARTITION BY ai.album_id
                           ORDER BY ai.sort_order ASC, ai.created_at DESC, ai.id ASC
                       ) AS rn
                FROM omni.photo_album_items ai
                JOIN omni.photo_items pi ON pi.id = ai.photo_id
                JOIN omni.file_nodes f ON f.id = pi.file_node_id
                WHERE ai.album_id IN (:albumIds)
                  AND pi.deleted_at IS NULL
                  AND f.is_deleted = false
                  AND pi.cover_file_id IS NOT NULL
            ) ranked
            WHERE ranked.rn = 1
            """, nativeQuery = true)
    List<PhotoAlbumFirstCoverProjection> findFirstActiveCoverFileIdsByAlbumIds(
            @Param("albumIds") Collection<UUID> albumIds);

    /**
     * 统计相册中的照片数量
     */
    long countByAlbumId(UUID albumId);

    /**
     * 统计相册内「未进回收站」的照片数量。
     *
     * <p>相册详情列表按活动照片过滤，卡片计数必须用同一口径，否则照片移入回收站后
     * 影集卡片仍显示旧数量。判定条件与 {@code findActiveByOwnerUserIdAndIdIn} 保持一致。</p>
     *
     * @param albumId 相册 ID
     * @return 活动照片数
     */
    @Query("""
            SELECT COUNT(item.id)
            FROM PhotoAlbumItem item
            JOIN PhotoItem photo ON photo.id = item.photoId
            JOIN FileNode file ON photo.fileNodeId = file.id
            WHERE item.albumId = :albumId
              AND file.deleted = false
              AND photo.deletedAt IS NULL
            """)
    long countActivePhotosByAlbumId(@Param("albumId") UUID albumId);

    /**
     * 按照片ID列表删除相册关联条目
     */
    void deleteByPhotoIdIn(List<UUID> photoIds);

    /**
     * 查询包含指定照片的相册ID列表
     */
    @Query("SELECT DISTINCT ai.albumId FROM PhotoAlbumItem ai WHERE ai.photoId IN :photoIds")
    List<UUID> findAlbumIdsByPhotoIdIn(@Param("photoIds") List<UUID> photoIds);
}
