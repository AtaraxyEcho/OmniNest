package com.omninest.modules.music.repository;

import com.omninest.modules.music.domain.MusicPlayHistory;
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
 * 提供音乐播放历史的持久化和用户维度查询能力。
 *
 * @author OmniNest
 */
public interface MusicPlayHistoryRepository extends JpaRepository<MusicPlayHistory, UUID> {
    /**
     * 查询用户最近五十条播放历史。
     *
     * @param ownerUserId 用户 ID
     * @return 按播放时间倒序排列的历史
     */
    List<MusicPlayHistory> findTop50ByOwnerUserIdAndPlayedAtGreaterThanEqualOrderByPlayedAtDesc(
            UUID ownerUserId,
            Instant cutoff
    );

    /**
     * 批量删除用户指定时间之前的播放历史。
     *
     * @param ownerUserId 用户 ID
     * @param cutoff 截止时间
     * @return 删除数量
     */
    @Modifying(clearAutomatically = true)
    @Query("DELETE FROM MusicPlayHistory h WHERE h.ownerUserId = :ownerUserId AND h.playedAt < :cutoff")
    int deleteExpiredHistory(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("cutoff") Instant cutoff
    );

    /**
     * 查询用户最后播放的本地音乐历史。
     *
     * @param ownerUserId 用户 ID
     * @return 本地音乐历史
     */
    Optional<MusicPlayHistory> findFirstByOwnerUserIdAndTrackIdIsNotNullOrderByPlayedAtDesc(UUID ownerUserId);

    /**
     * 分页查询用户播放历史，按播放时间倒序。
     *
     * @param ownerUserId 用户 ID
     * @param cutoff 只返回该时间之后的历史
     * @param pageable 分页参数
     * @return 播放历史分页
     */
    Page<MusicPlayHistory> findByOwnerUserIdAndPlayedAtGreaterThanEqualOrderByPlayedAtDesc(
            UUID ownerUserId,
            Instant cutoff,
            Pageable pageable
    );

    /**
     * 统计用户播放历史数量。
     *
     * @param ownerUserId 用户 ID
     * @return 历史数量
     */
    long countByOwnerUserId(UUID ownerUserId);

    /**
     * 删除用户指定本地曲目的播放历史。
     *
     * @param ownerUserId 用户 ID
     * @param trackIds 曲目 ID 集合
     */
    void deleteByOwnerUserIdAndTrackIdIn(UUID ownerUserId, Collection<UUID> trackIds);

    /**
     * 按 trackId 删除所有用户的播放历史（共享空间文件清理用）。
     *
     * @param trackIds 曲目 ID 集合
     */
    @Modifying(clearAutomatically = true)
    @Query("DELETE FROM MusicPlayHistory h WHERE h.trackId IN :trackIds")
    void deleteByTrackIdIn(@Param("trackIds") Collection<UUID> trackIds);
}
