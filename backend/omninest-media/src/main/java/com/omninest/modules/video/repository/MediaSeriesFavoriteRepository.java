package com.omninest.modules.video.repository;

import com.omninest.modules.video.domain.MediaSeriesFavorite;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface MediaSeriesFavoriteRepository extends JpaRepository<MediaSeriesFavorite, UUID> {
    boolean existsByOwnerUserIdAndSeriesId(UUID ownerUserId, UUID seriesId);

    /**
     * 统计用户收藏的系列总数（含剧集与动漫）。
     *
     * @param ownerUserId 所有者用户 ID
     * @return 系列收藏总数
     */
    long countByOwnerUserId(UUID ownerUserId);

    Optional<MediaSeriesFavorite> findByOwnerUserIdAndSeriesId(UUID ownerUserId, UUID seriesId);

    /**
     * 按收藏时间倒序查询用户的系列收藏。
     *
     * @param ownerUserId 所有者用户 ID
     * @return 系列收藏列表
     */
    List<MediaSeriesFavorite> findByOwnerUserIdOrderByCreatedAtDesc(UUID ownerUserId);

    List<MediaSeriesFavorite> findByOwnerUserIdAndSeriesIdIn(UUID ownerUserId, Collection<UUID> seriesIds);

    void deleteByOwnerUserIdAndSeriesIdIn(UUID ownerUserId, Collection<UUID> seriesIds);
}
