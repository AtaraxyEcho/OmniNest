package com.omninest.modules.video.repository;

import com.omninest.modules.video.domain.MediaVideoCollection;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface MediaVideoCollectionRepository extends JpaRepository<MediaVideoCollection, UUID> {
    List<MediaVideoCollection> findByOwnerUserIdOrderByUpdatedAtDesc(UUID ownerUserId);

    /**
     * 统计用户创建的合集总数。
     *
     * @param ownerUserId 所有者用户 ID
     * @return 合集总数
     */
    long countByOwnerUserId(UUID ownerUserId);

    long countByOwnerUserIdAndCollectionTypeNot(UUID ownerUserId, String collectionType);

    Optional<MediaVideoCollection> findByIdAndOwnerUserId(UUID id, UUID ownerUserId);

    Optional<MediaVideoCollection> findByOwnerUserIdAndCollectionType(UUID ownerUserId, String collectionType);

    @Modifying
    @Query(value = """
            INSERT INTO omni.media_video_collections
                (owner_user_id, name, collection_type, created_at, updated_at, version)
            VALUES (:ownerUserId, 'Watchlist', 'WATCHLIST', now(), now(), 0)
            ON CONFLICT (owner_user_id) WHERE collection_type = 'WATCHLIST' DO NOTHING
            """, nativeQuery = true)
    int insertWatchlistIfAbsent(@Param("ownerUserId") UUID ownerUserId);

    List<MediaVideoCollection> findByOwnerUserIdAndCoverFileIdIn(UUID ownerUserId, Collection<UUID> fileIds);

    List<MediaVideoCollection> findByCoverFileIdIn(Collection<UUID> fileIds);

    List<MediaVideoCollection> findAllByIdInAndOwnerUserId(Collection<UUID> ids, UUID ownerUserId);

    void deleteByOwnerUserIdAndIdIn(UUID ownerUserId, Collection<UUID> ids);
}
