package com.omninest.modules.video.repository;

import com.omninest.modules.video.domain.MediaVideoCollection;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface MediaVideoCollectionRepository extends JpaRepository<MediaVideoCollection, UUID> {
    List<MediaVideoCollection> findByOwnerUserIdOrderByUpdatedAtDesc(UUID ownerUserId);

    /**
     * 统计用户创建的合集总数。
     *
     * @param ownerUserId 所有者用户 ID
     * @return 合集总数
     */
    long countByOwnerUserId(UUID ownerUserId);

    Optional<MediaVideoCollection> findByIdAndOwnerUserId(UUID id, UUID ownerUserId);

    List<MediaVideoCollection> findByOwnerUserIdAndCoverFileIdIn(UUID ownerUserId, Collection<UUID> fileIds);

    List<MediaVideoCollection> findByCoverFileIdIn(Collection<UUID> fileIds);

    List<MediaVideoCollection> findAllByIdInAndOwnerUserId(Collection<UUID> ids, UUID ownerUserId);

    void deleteByOwnerUserIdAndIdIn(UUID ownerUserId, Collection<UUID> ids);
}
