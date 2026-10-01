package com.omninest.modules.media.service;

import com.github.benmanes.caffeine.cache.Cache;
import com.github.benmanes.caffeine.cache.Caffeine;
import com.github.benmanes.caffeine.cache.Expiry;
import com.omninest.modules.file.port.MediaCoverDirectory;
import com.omninest.modules.music.domain.MusicAlbum;
import com.omninest.modules.music.domain.MusicTrack;
import com.omninest.modules.music.repository.MusicAlbumRepository;
import com.omninest.modules.music.repository.MusicTrackRepository;
import com.omninest.modules.reader.domain.ReaderItem;
import com.omninest.modules.reader.repository.ReaderItemRepository;
import com.omninest.modules.video.domain.MediaMovie;
import com.omninest.modules.video.domain.MediaTvSeason;
import com.omninest.modules.video.domain.MediaTvSeries;
import com.omninest.modules.video.domain.MediaVideoItem;
import com.omninest.modules.video.repository.MediaMovieRepository;
import com.omninest.modules.video.repository.MediaTvSeasonRepository;
import com.omninest.modules.video.repository.MediaTvSeriesRepository;
import com.omninest.modules.video.repository.MediaVideoItemRepository;
import java.time.Duration;
import java.util.ArrayList;
import java.util.Collection;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.TimeUnit;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 媒体封面反查端口的 media 模块实现。
 *
 * <p>三条解析链：音乐 曲目封面→专辑封面回退；影视 条目→季海报→
 * 影片海报→剧集海报回退；阅读 条目封面。差异化 TTL：正结果 10 分钟、
 * 负结果 60 秒——媒体入库前的"无封面"不被长期缓存，导入完成约一分钟后
 * 列表即可解析到新封面。</p>
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class MediaCoverDirectoryImpl implements MediaCoverDirectory {

    private static final Duration POSITIVE_TTL = Duration.ofMinutes(10);
    private static final Duration NEGATIVE_TTL = Duration.ofSeconds(60);

    private final MusicTrackRepository musicTrackRepository;
    private final MusicAlbumRepository musicAlbumRepository;
    private final MediaVideoItemRepository videoItemRepository;
    private final MediaMovieRepository movieRepository;
    private final MediaTvSeasonRepository seasonRepository;
    private final MediaTvSeriesRepository seriesRepository;
    private final ReaderItemRepository readerItemRepository;

    private final Cache<UUID, Optional<UUID>> cache = Caffeine.newBuilder()
            .maximumSize(10_000)
            .expireAfter(new CoverExpiry())
            .build();

    @Override
    @Transactional(readOnly = true)
    public Map<UUID, UUID> resolveCoverFileIds(UUID ownerUserId, Collection<UUID> fileNodeIds) {
        if (ownerUserId == null || fileNodeIds == null || fileNodeIds.isEmpty()) {
            return Map.of();
        }
        Map<UUID, UUID> result = new HashMap<>();
        List<UUID> misses = new ArrayList<>();
        Set<UUID> distinct = new HashSet<>(fileNodeIds);
        for (UUID fileId : distinct) {
            Optional<UUID> cached = cache.getIfPresent(fileId);
            if (cached == null) {
                misses.add(fileId);
            } else {
                cached.ifPresent(coverId -> result.put(fileId, coverId));
            }
        }
        if (misses.isEmpty()) {
            return result;
        }
        Map<UUID, UUID> resolved = resolveUncached(ownerUserId, misses);
        for (UUID fileId : misses) {
            UUID coverId = resolved.get(fileId);
            cache.put(fileId, Optional.ofNullable(coverId));
            if (coverId != null) {
                result.put(fileId, coverId);
            }
        }
        return result;
    }

    /** 无缓存批量解析：三链各一次 IN 查询 + 回退实体补查。 */
    private Map<UUID, UUID> resolveUncached(UUID ownerUserId, List<UUID> fileNodeIds) {
        Map<UUID, UUID> covers = new HashMap<>();
        resolveMusicCovers(fileNodeIds, covers);
        resolveVideoCovers(ownerUserId, fileNodeIds, covers);
        resolveReaderCovers(fileNodeIds, covers);
        return covers;
    }

    private void resolveMusicCovers(List<UUID> fileNodeIds, Map<UUID, UUID> covers) {
        List<MusicTrack> tracks = musicTrackRepository.findByFileNodeIdIn(fileNodeIds);
        if (tracks.isEmpty()) {
            return;
        }
        Set<UUID> albumIdsNeedingFallback = new HashSet<>();
        for (MusicTrack track : tracks) {
            if (track.getCoverFileId() != null) {
                covers.put(track.getFileNodeId(), track.getCoverFileId());
            } else if (track.getAlbumId() != null) {
                albumIdsNeedingFallback.add(track.getAlbumId());
            }
        }
        if (albumIdsNeedingFallback.isEmpty()) {
            return;
        }
        Map<UUID, UUID> albumCovers = new HashMap<>();
        for (MusicAlbum album : musicAlbumRepository.findAllById(albumIdsNeedingFallback)) {
            if (album.getCoverFileId() != null) {
                albumCovers.put(album.getId(), album.getCoverFileId());
            }
        }
        for (MusicTrack track : tracks) {
            if (!covers.containsKey(track.getFileNodeId()) && track.getAlbumId() != null) {
                UUID albumCover = albumCovers.get(track.getAlbumId());
                if (albumCover != null) {
                    covers.put(track.getFileNodeId(), albumCover);
                }
            }
        }
    }

    private void resolveVideoCovers(UUID ownerUserId, List<UUID> fileNodeIds, Map<UUID, UUID> covers) {
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

    private void resolveReaderCovers(List<UUID> fileNodeIds, Map<UUID, UUID> covers) {
        for (ReaderItem item : readerItemRepository.findByFileNodeIdIn(fileNodeIds)) {
            if (item.getCoverFileId() != null) {
                covers.put(item.getFileNodeId(), item.getCoverFileId());
            }
        }
    }

    /** 差异化过期：有封面长缓存，无封面短缓存。 */
    private static final class CoverExpiry implements Expiry<UUID, Optional<UUID>> {
        @Override
        public long expireAfterCreate(UUID key, Optional<UUID> value, long currentTime) {
            return after(value, currentTime);
        }

        @Override
        public long expireAfterUpdate(UUID key, Optional<UUID> value, long currentTime, long currentDuration) {
            return after(value, currentTime);
        }

        @Override
        public long expireAfterRead(UUID key, Optional<UUID> value, long currentTime, long currentDuration) {
            return currentDuration;
        }

        private long after(Optional<UUID> value, long currentTime) {
            Duration ttl = value.isPresent() ? POSITIVE_TTL : NEGATIVE_TTL;
            return TimeUnit.NANOSECONDS.convert(ttl.toNanos(), TimeUnit.NANOSECONDS);
        }
    }
}
