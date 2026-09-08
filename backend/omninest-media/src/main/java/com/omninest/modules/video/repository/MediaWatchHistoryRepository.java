package com.omninest.modules.video.repository;

import com.omninest.modules.video.domain.MediaWatchHistory;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface MediaWatchHistoryRepository extends JpaRepository<MediaWatchHistory, UUID> {
    List<MediaWatchHistory> findByOwnerUserIdOrderByPlayedAtDesc(UUID ownerUserId);

    /**
     * 统计用户观看历史总数。
     *
     * @param ownerUserId 所有者用户 ID
     * @return 历史记录总数
     */
    long countByOwnerUserId(UUID ownerUserId);

    Optional<MediaWatchHistory> findFirstByOwnerUserIdAndVideoItemIdOrderByPlayedAtDesc(UUID ownerUserId, UUID videoItemId);

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
