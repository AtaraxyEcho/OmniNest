package com.omninest.modules.video.repository;

import com.omninest.modules.video.domain.MediaVideoFavorite;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface MediaVideoFavoriteRepository extends JpaRepository<MediaVideoFavorite, UUID> {
    boolean existsByOwnerUserIdAndVideoItemId(UUID ownerUserId, UUID videoItemId);

    /**
     * 统计用户收藏的影片条目总数。
     *
     * @param ownerUserId 所有者用户 ID
     * @return 收藏总数
     */
    long countByOwnerUserId(UUID ownerUserId);

    Optional<MediaVideoFavorite> findByOwnerUserIdAndVideoItemId(UUID ownerUserId, UUID videoItemId);

    List<MediaVideoFavorite> findByOwnerUserIdOrderByCreatedAtDesc(UUID ownerUserId);

    void deleteByOwnerUserIdAndVideoItemIdIn(UUID ownerUserId, Collection<UUID> videoItemIds);

    /**
     * 按 videoItemId 删除所有用户的收藏（共享空间文件清理用）。
     */
    @Modifying(clearAutomatically = true)
    @Query("DELETE FROM MediaVideoFavorite f WHERE f.videoItemId IN :videoItemIds")
    void deleteByVideoItemIdIn(@Param("videoItemIds") Collection<UUID> videoItemIds);
}
