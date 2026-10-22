package com.omninest.modules.video.repository;

import com.omninest.modules.video.domain.MediaWatchHistory;
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

public interface MediaWatchHistoryRepository extends JpaRepository<MediaWatchHistory, UUID> {
    List<MediaWatchHistory> findByOwnerUserIdOrderByPlayedAtDesc(UUID ownerUserId);

    /**
     * 分页查询用户观看历史，按播放时间倒序，供历史列表滚动加载。
     */
    Page<MediaWatchHistory> findPageByOwnerUserIdOrderByPlayedAtDesc(UUID ownerUserId, Pageable pageable);

    /**
     * 统计用户观看历史总数。
     *
     * @param ownerUserId 所有者用户 ID
     * @return 历史记录总数
     */
    long countByOwnerUserId(UUID ownerUserId);

    Optional<MediaWatchHistory> findFirstByOwnerUserIdAndVideoItemIdOrderByPlayedAtDesc(UUID ownerUserId, UUID videoItemId);

    /**
     * 查询用户在某系列下的全部观看历史，按播放时间倒序。
     *
     * <p>详情页续播只需要当前系列的历史，拉全量历史再在客户端过滤既浪费
     * 带宽，也会在超过历史分页上限后丢失旧进度。</p>
     *
     * @param ownerUserId 所有者用户标识
     * @param seriesId 系列标识
     * @return 该系列的观看历史
     */
    @Query("""
            SELECT h FROM MediaWatchHistory h
            JOIN MediaVideoItem i ON i.id = h.videoItemId
            WHERE h.ownerUserId = :ownerUserId
              AND i.seriesId = :seriesId
            ORDER BY h.playedAt DESC
            """)
    List<MediaWatchHistory> findByOwnerUserIdAndSeriesIdOrderByPlayedAtDesc(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("seriesId") UUID seriesId);

    @Modifying
    @Query("delete from MediaWatchHistory h where h.ownerUserId = :ownerUserId and h.videoItemId in :videoItemIds")
    void deleteByOwnerUserIdAndVideoItemIdIn(@Param("ownerUserId") UUID ownerUserId, @Param("videoItemIds") Collection<UUID> videoItemIds);

    void deleteByOwnerUserIdAndId(UUID ownerUserId, UUID id);

    @Modifying
    @Query("delete from MediaWatchHistory h where h.ownerUserId = :ownerUserId")
    void deleteByOwnerUserId(@Param("ownerUserId") UUID ownerUserId);

    /**
     * 按 videoItemId 删除所有用户的观看历史（共享空间文件清理用）。
     */
    @Modifying(clearAutomatically = true)
    @Query("DELETE FROM MediaWatchHistory h WHERE h.videoItemId IN :videoItemIds")
    void deleteByVideoItemIdIn(@Param("videoItemIds") Collection<UUID> videoItemIds);
}
