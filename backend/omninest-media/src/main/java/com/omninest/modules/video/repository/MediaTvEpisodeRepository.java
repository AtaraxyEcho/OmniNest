package com.omninest.modules.video.repository;

import com.omninest.modules.video.domain.MediaTvEpisode;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface MediaTvEpisodeRepository extends JpaRepository<MediaTvEpisode, UUID> {
    Optional<MediaTvEpisode> findByOwnerUserIdAndSeriesIdAndSeasonNumberAndEpisodeNumber(
            UUID ownerUserId, UUID seriesId, Integer seasonNumber, Integer episodeNumber);

    List<MediaTvEpisode> findByOwnerUserIdAndSeriesIdOrderBySeasonNumberAscEpisodeNumberAsc(
            UUID ownerUserId, UUID seriesId);

    List<MediaTvEpisode> findByOwnerUserIdAndSeriesIdAndSeasonNumberOrderByEpisodeNumberAsc(
            UUID ownerUserId, UUID seriesId, Integer seasonNumber);

    List<MediaTvEpisode> findByOwnerUserIdAndTmdbIdAndSeriesIdIsNull(UUID ownerUserId, Integer tmdbId);

    long countByOwnerUserIdAndSeriesIdAndSeasonNumber(UUID ownerUserId, UUID seriesId, Integer seasonNumber);

    long countByOwnerUserIdAndSeriesId(UUID ownerUserId, UUID seriesId);

    List<MediaTvEpisode> findAllByIdInAndOwnerUserId(Collection<UUID> ids, UUID ownerUserId);

    void deleteByOwnerUserIdAndIdIn(UUID ownerUserId, Collection<UUID> ids);

    List<MediaTvEpisode> findByOwnerUserIdAndStillFileIdIn(UUID ownerUserId, Collection<UUID> fileIds);

    List<MediaTvEpisode> findByStillFileIdIn(Collection<UUID> fileIds);
}
