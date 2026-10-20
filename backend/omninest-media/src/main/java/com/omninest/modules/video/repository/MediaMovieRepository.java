package com.omninest.modules.video.repository;

import com.omninest.modules.video.domain.MediaMovie;
import java.time.LocalDate;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface MediaMovieRepository extends JpaRepository<MediaMovie, UUID> {
    Optional<MediaMovie> findByTmdbIdAndOwnerUserId(Integer tmdbId, UUID ownerUserId);

    Optional<MediaMovie> findByIdAndOwnerUserId(UUID id, UUID ownerUserId);

    Optional<MediaMovie> findByOwnerUserIdAndLibrarySourceIdAndTitleAndReleaseDate(
            UUID ownerUserId, UUID librarySourceId, String title, LocalDate releaseDate);

    Optional<MediaMovie> findByOwnerUserIdAndLibrarySourceIdAndTitleAndReleaseDateIsNull(
            UUID ownerUserId, UUID librarySourceId, String title);

    List<MediaMovie> findAllByIdInAndOwnerUserId(Collection<UUID> ids, UUID ownerUserId);

    void deleteByOwnerUserIdAndIdIn(UUID ownerUserId, Collection<UUID> ids);

    List<MediaMovie> findByOwnerUserIdAndPosterFileIdIn(UUID ownerUserId, Collection<UUID> fileIds);

    List<MediaMovie> findByOwnerUserIdAndBackdropFileIdIn(UUID ownerUserId, Collection<UUID> fileIds);

    List<MediaMovie> findByPosterFileIdIn(Collection<UUID> fileIds);

    List<MediaMovie> findByBackdropFileIdIn(Collection<UUID> fileIds);

}
