package com.omninest.modules.video.repository;

import com.omninest.modules.video.domain.MediaTvSeason;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface MediaTvSeasonRepository extends JpaRepository<MediaTvSeason, UUID> {
    List<MediaTvSeason> findByOwnerUserIdAndSeriesIdOrderBySeasonNumberAsc(UUID ownerUserId, UUID seriesId);

    List<MediaTvSeason> findByOwnerUserIdAndSeriesIdIn(
            UUID ownerUserId, Collection<UUID> seriesIds);

    Optional<MediaTvSeason> findByOwnerUserIdAndSeriesIdAndSeasonNumber(UUID ownerUserId, UUID seriesId, Integer seasonNumber);

    List<MediaTvSeason> findAllByIdInAndOwnerUserId(Collection<UUID> ids, UUID ownerUserId);

    void deleteByOwnerUserIdAndIdIn(UUID ownerUserId, Collection<UUID> ids);

    List<MediaTvSeason> findByOwnerUserIdAndPosterFileIdIn(UUID ownerUserId, Collection<UUID> fileIds);

    List<MediaTvSeason> findByPosterFileIdIn(Collection<UUID> fileIds);
}
