package com.omninest.modules.video.repository;

import com.omninest.modules.video.domain.MediaVideoCollectionItem;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface MediaVideoCollectionItemRepository extends JpaRepository<MediaVideoCollectionItem, UUID> {
    long countByOwnerUserIdAndCollectionId(UUID ownerUserId, UUID collectionId);

    List<MediaVideoCollectionItem> findByOwnerUserIdAndCollectionIdOrderBySortOrderAsc(UUID ownerUserId, UUID collectionId);

    Optional<MediaVideoCollectionItem> findByOwnerUserIdAndCollectionIdAndVideoItemId(
            UUID ownerUserId,
            UUID collectionId,
            UUID videoItemId
    );

    void deleteByOwnerUserIdAndVideoItemIdIn(UUID ownerUserId, Collection<UUID> videoItemIds);

    /**
     * 按 videoItemId 删除所有用户的合集条目（共享空间文件清理用）。
     */
    @Modifying(clearAutomatically = true)
    @Query("DELETE FROM MediaVideoCollectionItem ci WHERE ci.videoItemId IN :videoItemIds")
    void deleteByVideoItemIdIn(@Param("videoItemIds") Collection<UUID> videoItemIds);

    List<MediaVideoCollectionItem> findByOwnerUserIdAndVideoItemIdIn(UUID ownerUserId, Collection<UUID> videoItemIds);

    void deleteByOwnerUserIdAndCollectionId(UUID ownerUserId, UUID collectionId);

    void deleteByOwnerUserIdAndCollectionIdAndVideoItemId(UUID ownerUserId, UUID collectionId, UUID videoItemId);

    @Query("""
            select ci.collectionId as collectionId, count(ci) as cnt
            from MediaVideoCollectionItem ci
            where ci.ownerUserId = :ownerUserId and ci.collectionId in :collectionIds
            group by ci.collectionId
            """)
    List<Object[]> countByOwnerUserIdAndCollectionIdIn(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("collectionIds") Collection<UUID> collectionIds);

    @Query("""
            select count(item) from MediaVideoCollectionItem item
            where item.ownerUserId = :ownerUserId
              and item.collectionId = :collectionId
              and item.videoItemId not in :excludedVideoItemIds
            """)
    long countItemsOutsideTarget(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("collectionId") UUID collectionId,
            @Param("excludedVideoItemIds") Collection<UUID> excludedVideoItemIds
    );
}
