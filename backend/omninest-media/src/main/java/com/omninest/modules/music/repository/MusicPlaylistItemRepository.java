package com.omninest.modules.music.repository;

import com.omninest.modules.music.domain.MusicPlaylistItem;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface MusicPlaylistItemRepository extends JpaRepository<MusicPlaylistItem, UUID> {
    List<MusicPlaylistItem> findByOwnerUserIdAndPlaylistIdOrderBySortOrderAscCreatedAtAsc(UUID ownerUserId, UUID playlistId);

    /**
     * 查询歌单首条目（排序最前），用于封面取值，避免加载整单条目。
     *
     * @param ownerUserId 所属用户标识
     * @param playlistId 歌单标识
     * @return 首条目
     */
    Optional<MusicPlaylistItem> findTopByOwnerUserIdAndPlaylistIdOrderBySortOrderAscCreatedAtAsc(
            UUID ownerUserId,
            UUID playlistId
    );

    /**
     * 按歌单和曲目顺序批量查询用户的歌单项。
     *
     * @param ownerUserId 所属用户标识
     * @param playlistIds 歌单标识集合
     * @return 已按歌单、排序值和创建时间排序的歌单项
     */
    @Query("""
            select item from MusicPlaylistItem item
            where item.ownerUserId = :ownerUserId and item.playlistId in :playlistIds
            order by item.playlistId, item.sortOrder, item.createdAt
            """)
    List<MusicPlaylistItem> findOrderedByOwnerAndPlaylistIds(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("playlistIds") Collection<UUID> playlistIds
    );

    long countByOwnerUserIdAndPlaylistId(UUID ownerUserId, UUID playlistId);

    void deleteByOwnerUserIdAndPlaylistIdAndTrackIdIn(UUID ownerUserId, UUID playlistId, List<UUID> trackIds);

    void deleteByOwnerUserIdAndPlaylistId(UUID ownerUserId, UUID playlistId);

    void deleteByOwnerUserIdAndTrackIdIn(UUID ownerUserId, Collection<UUID> trackIds);

    /**
     * 按 trackId 删除所有用户的播放列表项（共享空间文件清理用）。
     */
    @Modifying(clearAutomatically = true)
    @Query("DELETE FROM MusicPlaylistItem pi WHERE pi.trackId IN :trackIds")
    void deleteByTrackIdIn(@Param("trackIds") Collection<UUID> trackIds);

    @Query("""
            select pi.playlistId as playlistId, count(pi) as cnt
            from MusicPlaylistItem pi
            where pi.ownerUserId = :ownerUserId and pi.playlistId in :playlistIds
            group by pi.playlistId
            """)
    List<Object[]> countByOwnerUserIdAndPlaylistIdIn(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("playlistIds") Collection<UUID> playlistIds);
}
