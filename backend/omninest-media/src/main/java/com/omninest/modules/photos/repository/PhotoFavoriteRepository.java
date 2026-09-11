package com.omninest.modules.photos.repository;

import com.omninest.modules.photos.domain.PhotoFavorite;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/**
 * 照片收藏仓储接口。
 *
 * @author OmniNest
 */
public interface PhotoFavoriteRepository extends JpaRepository<PhotoFavorite, UUID> {

    /**
     * 按用户查询收藏列表，按创建时间倒序
     */
    List<PhotoFavorite> findByOwnerUserIdOrderByCreatedAtDesc(UUID ownerUserId);

    /**
     * 按用户分页查询收藏列表，按创建时间倒序。
     */
    List<PhotoFavorite> findByOwnerUserIdOrderByCreatedAtDesc(UUID ownerUserId, Pageable pageable);

    /**
     * 统计用户收藏总数。
     */
    long countByOwnerUserId(UUID ownerUserId);

    /**
     * 批量查询用户收藏的照片标识。
     *
     * @param ownerUserId 用户标识
     * @param photoIds 照片标识集合
     * @return 已收藏照片标识
     */
    @Query("SELECT f.photoId FROM PhotoFavorite f "
            + "WHERE f.ownerUserId = :ownerUserId AND f.photoId IN :photoIds")
    List<UUID> findPhotoIdsByOwnerUserIdAndPhotoIdIn(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("photoIds") List<UUID> photoIds);

    /**
     * 按用户和照片查询收藏记录
     */
    Optional<PhotoFavorite> findByOwnerUserIdAndPhotoId(UUID ownerUserId, UUID photoId);

    /**
     * 判断用户是否已收藏指定照片
     */
    boolean existsByOwnerUserIdAndPhotoId(UUID ownerUserId, UUID photoId);

    /**
     * 按用户和照片删除收藏记录
     */
    void deleteByOwnerUserIdAndPhotoId(UUID ownerUserId, UUID photoId);

    /**
     * 按照片ID列表删除收藏记录
     */
    void deleteByPhotoIdIn(List<UUID> photoIds);
}
