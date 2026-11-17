package com.omninest.modules.video.repository;

import com.omninest.modules.video.domain.MediaLibraryAccess;
import java.util.Collection;
import java.util.List;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

/** 媒体库用户授权仓储。 */
public interface MediaLibraryAccessRepository extends JpaRepository<MediaLibraryAccess, UUID> {

    boolean existsByLibrarySourceIdAndUserId(UUID librarySourceId, UUID userId);

    List<MediaLibraryAccess> findByLibrarySourceIdOrderByCreatedAtAsc(UUID librarySourceId);

    List<MediaLibraryAccess> findByUserId(UUID userId);

    void deleteByLibrarySourceId(UUID librarySourceId);

    void deleteByLibrarySourceIdAndUserIdNotIn(UUID librarySourceId, Collection<UUID> userIds);

    void deleteByUserId(UUID userId);
}
