package com.omninest.modules.video.service;

import com.omninest.modules.media.service.MediaCoverContributor;
import com.omninest.modules.video.domain.MediaMovie;
import com.omninest.modules.video.domain.MediaTvSeason;
import com.omninest.modules.video.domain.MediaTvSeries;
import com.omninest.modules.video.domain.MediaVideoItem;
import com.omninest.modules.video.repository.MediaMovieRepository;
import com.omninest.modules.video.repository.MediaTvSeasonRepository;
import com.omninest.modules.video.repository.MediaTvSeriesRepository;
import com.omninest.modules.video.repository.MediaVideoItemRepository;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

/**
 * 影视域封面贡献者：条目回退顺序为季海报、影片海报、剧集海报。
 *
 * @author OmniNest
 */
@Component
@RequiredArgsConstructor
public class VideoCoverContributor implements MediaCoverContributor {

    private final MediaVideoItemRepository videoItemRepository;
    private final MediaMovieRepository movieRepository;
    private final MediaTvSeasonRepository seasonRepository;
    private final MediaTvSeriesRepository seriesRepository;

    @Override
    public void contribute(UUID ownerUserId, List<UUID> fileNodeIds, Map<UUID, UUID> covers) {
        List<MediaVideoItem> items = videoItemRepository
                .findByOwnerUserIdAndFileNodeIdIn(ownerUserId, fileNodeIds);
        if (items.isEmpty()) {
            return;
        }
        Set<UUID> movieIds = new HashSet<>();
        Set<UUID> seasonIds = new HashSet<>();
        Set<UUID> seriesIds = new HashSet<>();
        for (MediaVideoItem item : items) {
            if (item.getMovieId() != null) {
                movieIds.add(item.getMovieId());
            }
            if (item.getSeasonId() != null) {
                seasonIds.add(item.getSeasonId());
            }
            if (item.getSeriesId() != null) {
                seriesIds.add(item.getSeriesId());
            }
        }
        Map<UUID, UUID> moviePosters = new HashMap<>();
        if (!movieIds.isEmpty()) {
            for (MediaMovie movie : movieRepository.findAllById(movieIds)) {
                if (movie.getPosterFileId() != null) {
                    moviePosters.put(movie.getId(), movie.getPosterFileId());
                }
            }
        }
        Map<UUID, UUID> seasonPosters = new HashMap<>();
        if (!seasonIds.isEmpty()) {
            for (MediaTvSeason season : seasonRepository.findAllById(seasonIds)) {
                if (season.getPosterFileId() != null) {
                    seasonPosters.put(season.getId(), season.getPosterFileId());
                }
            }
        }
        Map<UUID, UUID> seriesPosters = new HashMap<>();
        if (!seriesIds.isEmpty()) {
            for (MediaTvSeries series : seriesRepository.findAllById(seriesIds)) {
                if (series.getPosterFileId() != null) {
                    seriesPosters.put(series.getId(), series.getPosterFileId());
                }
            }
        }
        for (MediaVideoItem item : items) {
            UUID poster = seasonPosters.get(item.getSeasonId());
            if (poster == null) {
                poster = moviePosters.get(item.getMovieId());
            }
            if (poster == null) {
                poster = seriesPosters.get(item.getSeriesId());
            }
            if (poster != null) {
                covers.put(item.getFileNodeId(), poster);
            }
        }
    }
}
