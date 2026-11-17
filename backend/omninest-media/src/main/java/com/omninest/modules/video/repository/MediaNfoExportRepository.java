package com.omninest.modules.video.repository;

import com.omninest.modules.video.domain.MediaNfoExport;
import java.util.Collection;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface MediaNfoExportRepository extends JpaRepository<MediaNfoExport, UUID> {
    Optional<MediaNfoExport> findTopByOwnerUserIdAndVideoItemIdOrderByUpdatedAtDesc(UUID ownerUserId, UUID videoItemId);

    void deleteByOwnerUserIdAndVideoItemIdIn(UUID ownerUserId, Collection<UUID> videoItemIds);
}
