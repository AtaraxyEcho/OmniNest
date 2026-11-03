package com.omninest.modules.music.repository;

import com.omninest.modules.music.domain.MusicFavorite;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface MusicFavoriteRepository extends JpaRepository<MusicFavorite, UUID> {
    List<MusicFavorite> findByOwnerUserIdAndTrackIdIn(UUID ownerUserId, Collection<UUID> trackIds);

    /**
     * 按收藏时间倒序返回曲目 ID。
     *
     * <p>收藏只需要 ID：物化整个实体会把行数等量的托管对象放进持久化上下文，
     * 而调用方紧接着就丢弃它们。</p>
     *
     * @param ownerUserId 所有者用户 ID
     * @return 曲目 ID 列表，按收藏时间倒序
     */
    @Query("""
            select favorite.trackId from MusicFavorite favorite
            where favorite.ownerUserId = :ownerUserId
            order by favorite.createdAt desc
            """)
    List<UUID> findFavoriteTrackIdsByOwnerUserId(@Param("ownerUserId") UUID ownerUserId);

    Optional<MusicFavorite> findByOwnerUserIdAndTrackId(UUID ownerUserId, UUID trackId);

    boolean existsByOwnerUserIdAndTrackId(UUID ownerUserId, UUID trackId);

    void deleteByOwnerUserIdAndTrackId(UUID ownerUserId, UUID trackId);

    void deleteByOwnerUserIdAndTrackIdIn(UUID ownerUserId, Collection<UUID> trackIds);

    /**
     * 按 trackId 删除所有用户的收藏（共享空间文件清理用）。
     */
    @Modifying(clearAutomatically = true)
    @Query("DELETE FROM MusicFavorite f WHERE f.trackId IN :trackIds")
    void deleteByTrackIdIn(@Param("trackIds") Collection<UUID> trackIds);
}
