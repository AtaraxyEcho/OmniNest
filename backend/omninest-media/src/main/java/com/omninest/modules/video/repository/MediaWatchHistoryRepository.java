package com.omninest.modules.video.repository;

import com.omninest.modules.video.domain.MediaWatchHistory;
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
     * 原子写入单个视频条目的观看历史。
     *
     * <p>同一条目每个用户只保留一行：先查后插的写法在并发上报（起播与首个心跳
     * 同时到达）下会插出多行，历史列表与续播位置都会分裂。进度行本身已按
     * {@code ON CONFLICT} 收口，历史行必须同口径。</p>
     *
     * @param id 新行标识；冲突时不使用
     * @param ownerUserId 所有者用户 ID
     * @param videoItemId 视频条目 ID
     * @param positionSeconds 播放位置
     * @param durationSeconds 视频总时长
     * @param completed 是否看完
     * @param playedAt 播放记录时间
     * @return 插入或更新的行数
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query(value = """
            INSERT INTO omni.media_watch_history (
                id, owner_user_id, video_item_id, position_seconds, duration_seconds,
                completed, played_at, version
            ) VALUES (
                :id, :ownerUserId, :videoItemId, :positionSeconds, :durationSeconds,
                :completed, :playedAt, 0
            )
            ON CONFLICT (owner_user_id, video_item_id) DO UPDATE SET
                position_seconds = EXCLUDED.position_seconds,
                duration_seconds = EXCLUDED.duration_seconds,
                completed = EXCLUDED.completed,
                played_at = EXCLUDED.played_at,
                version = media_watch_history.version + 1
            """, nativeQuery = true)
    int upsertWatched(
            @Param("id") UUID id,
            @Param("ownerUserId") UUID ownerUserId,
            @Param("videoItemId") UUID videoItemId,
            @Param("positionSeconds") long positionSeconds,
            @Param("durationSeconds") long durationSeconds,
            @Param("completed") boolean completed,
            @Param("playedAt") Instant playedAt
    );

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
