package com.omninest.modules.photos.repository;

import com.omninest.modules.photos.domain.PhotoTag;
import java.util.List;
import java.util.UUID;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/**
 * 照片标签仓储接口
 */
public interface PhotoTagRepository extends JpaRepository<PhotoTag, UUID> {

    /**
     * 按用户和照片查询所有标签
     */
    List<PhotoTag> findByOwnerUserIdAndPhotoId(UUID ownerUserId, UUID photoId);

    /**
     * 按用户和标签名分页查询照片标签，按创建时间倒序。
     *
     * <p>兼容列表入口没有分页参数，但查询必须有界，避免单个标签命中整库时一次拉全量。</p>
     */
    List<PhotoTag> findByOwnerUserIdAndTagOrderByCreatedAtDesc(
            UUID ownerUserId,
            String tag,
            Pageable pageable);

    /**
     * 分页查询标签下的有效照片标签行：先剔除已删除或进回收站的照片，再分页。
     *
     * <p>沿用上一个方法的分页语义会在页内混入已删照片，剔除后单页条数不足 size
     * 且总数虚高；排序仍按打标签时间，保持列表顺序不变。</p>
     */
    @Query("""
            select pt from PhotoTag pt
            where pt.ownerUserId = :ownerUserId and pt.tag = :tag
              and exists (
                    select 1 from PhotoItem photo
                    join FileNode file on photo.fileNodeId = file.id
                    where photo.id = pt.photoId
                      and photo.ownerUserId = :ownerUserId
                      and photo.deletedAt is null
                      and file.deleted = false
                  )
            order by pt.createdAt desc
            """)
    Page<PhotoTag> findActiveByOwnerUserIdAndTag(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("tag") String tag,
            Pageable pageable
    );

    /**
     * 按用户和照片ID列表批量查询标签
     */
    List<PhotoTag> findByOwnerUserIdAndPhotoIdIn(UUID ownerUserId, List<UUID> photoIds);

    /**
     * 按用户、照片和标签名删除标签
     */
    void deleteByOwnerUserIdAndPhotoIdAndTag(UUID ownerUserId, UUID photoId, String tag);

    /**
     * 按用户和照片ID列表批量删除标签
     */
    void deleteByOwnerUserIdAndPhotoIdIn(UUID ownerUserId, List<UUID> photoIds);

    /**
     * 判断标签是否已存在
     */
    boolean existsByOwnerUserIdAndPhotoIdAndTag(UUID ownerUserId, UUID photoId, String tag);

    /**
     * 查询用户所有不重复的标签名
     */
    @Query("SELECT DISTINCT t.tag FROM PhotoTag t WHERE t.ownerUserId = :ownerUserId ORDER BY t.tag")
    List<String> findDistinctTagsByOwnerUserId(@Param("ownerUserId") UUID ownerUserId);

    /**
     * 按照片 ID 删除所有标签
     */
    void deleteByPhotoId(UUID photoId);
}
