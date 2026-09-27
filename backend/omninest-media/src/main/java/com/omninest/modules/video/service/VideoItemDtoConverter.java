package com.omninest.modules.video.service;

import com.omninest.modules.video.domain.MediaType;
import com.omninest.modules.media.domain.AssetType;
import com.omninest.modules.media.domain.ResourceType;
import com.omninest.modules.file.service.FileContentAvailabilityQueryService;
import com.omninest.modules.file.service.FileQueryService;
import com.omninest.modules.video.domain.ContentAsset;
import com.omninest.modules.video.repository.ContentAssetRepository;
import com.omninest.modules.video.domain.MediaMovie;
import com.omninest.modules.video.domain.MediaTvEpisode;
import com.omninest.modules.video.domain.MediaTvSeries;
import com.omninest.modules.video.domain.MediaVideoItem;
import com.omninest.modules.video.dto.MovieDtos.CastMemberDto;
import com.omninest.modules.video.dto.MovieDtos.CrewMemberDto;
import com.omninest.modules.video.dto.MovieDtos.MovieLibraryItemDto;
import com.omninest.modules.video.dto.MovieDtos.MovieVideoItemDto;
import com.omninest.modules.video.repository.MediaMovieRepository;
import com.omninest.modules.video.repository.MediaTvEpisodeRepository;
import com.omninest.modules.video.repository.MediaTvSeriesRepository;
import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.UUID;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

/**
 * 视频条目 DTO 转换器，支持批量加载关联实体以避免 N+1 查询。
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class VideoItemDtoConverter {
    private final MediaMovieRepository movieRepository;
    private final MediaTvEpisodeRepository episodeRepository;
    private final MediaTvSeriesRepository tvSeriesRepository;
    private final FileQueryService fileQueryService;
    private final VideoCatalogMappers catalogMappers;
    private final FileContentAvailabilityQueryService fileContentAvailabilityQueryService;
    private final ContentAssetRepository contentAssetRepository;
    private final MediaPlaybackTokenService mediaPlaybackTokenService;

    /**
     * 批量转换，内部批量加载 movie/episode/series，消除 N+1。
     */
    public List<MovieVideoItemDto> toVideoDtos(UUID requesterUserId, List<MediaVideoItem> items) {
        if (items.isEmpty()) {
            return List.of();
        }
        BatchIndex index = buildBatchIndex(items);
        return items.stream()
                .map(item -> toVideoDto(requesterUserId, item, index))
                .toList();
    }

    /**
     * 批量转换影视库卡片，仅生成列表展示所需字段。
     */
    public List<MovieLibraryItemDto> toLibraryDtos(UUID requesterUserId, List<MediaVideoItem> items) {
        if (items.isEmpty()) {
            return List.of();
        }
        BatchIndex index = buildBatchIndex(items);
        return items.stream()
                .map(item -> toLibraryDto(requesterUserId, item, index))
                .toList();
    }

    /**
     * 单条转换，只加载必要的关联实体（最多 3 次查询，而非 findAllById）。
     */
    public MovieVideoItemDto toVideoDto(UUID requesterUserId, MediaVideoItem item) {
        UUID catalogOwnerUserId = item.getOwnerUserId();
        Map<UUID, MediaMovie> movieMap = new LinkedHashMap<>();
        if (item.getMovieId() != null) {
            movieRepository.findById(item.getMovieId())
                    .ifPresent(m -> movieMap.put(item.getMovieId(), m));
        }
        Map<UUID, MediaTvEpisode> episodeMap = new LinkedHashMap<>();
        if (item.getEpisodeId() != null) {
            episodeRepository.findById(item.getEpisodeId())
                    .ifPresent(e -> episodeMap.put(item.getEpisodeId(), e));
        }
        Map<UUID, MediaTvSeries> seriesMap = new LinkedHashMap<>();
        if (item.getSeriesId() != null) {
            tvSeriesRepository.findById(item.getSeriesId())
                    .ifPresent(s -> seriesMap.put(item.getSeriesId(), s));
        }
        // 加载 ContentAsset 主资源，作为前端展示的权威来源。
        Map<UUID, UUID> moviePosterAssetMap = new LinkedHashMap<>();
        Map<UUID, UUID> movieBackdropAssetMap = new LinkedHashMap<>();
        Map<UUID, UUID> seriesPosterAssetMap = new LinkedHashMap<>();
        Map<UUID, UUID> seriesBackdropAssetMap = new LinkedHashMap<>();
        if (item.getMovieId() != null) {
            putPrimaryAsset(
                    catalogOwnerUserId,
                    ResourceType.MOVIE.getValue(),
                    item.getMovieId(),
                    AssetType.POSTER.getValue(),
                    moviePosterAssetMap
            );
            putPrimaryAsset(
                    catalogOwnerUserId,
                    ResourceType.MOVIE.getValue(),
                    item.getMovieId(),
                    AssetType.BACKDROP.getValue(),
                    movieBackdropAssetMap
            );
        }
        if (item.getSeriesId() != null) {
            putPrimaryAsset(
                    catalogOwnerUserId,
                    ResourceType.TV_SERIES.getValue(),
                    item.getSeriesId(),
                    AssetType.POSTER.getValue(),
                    seriesPosterAssetMap
            );
            putPrimaryAsset(
                    catalogOwnerUserId,
                    ResourceType.TV_SERIES.getValue(),
                    item.getSeriesId(),
                    AssetType.BACKDROP.getValue(),
                    seriesBackdropAssetMap
            );
        }
        BatchIndex index = new BatchIndex(movieMap, episodeMap, seriesMap,
                moviePosterAssetMap, movieBackdropAssetMap,
                seriesPosterAssetMap, seriesBackdropAssetMap,
                loadAvailability(List.of(item.getFileNodeId())));
        return toVideoDto(requesterUserId, item, index);
    }

    private record BatchIndex(
            Map<UUID, MediaMovie> movieMap,
            Map<UUID, MediaTvEpisode> episodeMap,
            Map<UUID, MediaTvSeries> seriesMap,
            Map<UUID, UUID> moviePosterAssetMap,
            Map<UUID, UUID> movieBackdropAssetMap,
            Map<UUID, UUID> seriesPosterAssetMap,
            Map<UUID, UUID> seriesBackdropAssetMap,
            Map<UUID, String> availabilityByFileNodeId
    ) {}

    private BatchIndex buildBatchIndex(List<MediaVideoItem> items) {
        List<UUID> movieIds = items.stream()
                .map(MediaVideoItem::getMovieId)
                .filter(Objects::nonNull)
                .distinct()
                .toList();
        Map<UUID, MediaMovie> movieMap = movieIds.isEmpty() ? Map.of()
                : movieRepository.findAllById(movieIds).stream()
                        .collect(Collectors.toMap(MediaMovie::getId, m -> m, (l, r) -> l, LinkedHashMap::new));

        List<UUID> episodeIds = items.stream()
                .map(MediaVideoItem::getEpisodeId)
                .filter(Objects::nonNull)
                .distinct()
                .toList();
        Map<UUID, MediaTvEpisode> episodeMap = episodeIds.isEmpty() ? Map.of()
                : episodeRepository.findAllById(episodeIds).stream()
                        .collect(Collectors.toMap(MediaTvEpisode::getId, e -> e, (l, r) -> l, LinkedHashMap::new));

        List<UUID> seriesIds = items.stream()
                .map(MediaVideoItem::getSeriesId)
                .filter(Objects::nonNull)
                .distinct()
                .toList();
        Map<UUID, MediaTvSeries> seriesMap = seriesIds.isEmpty() ? Map.of()
                : tvSeriesRepository.findAllById(seriesIds).stream()
                        .collect(Collectors.toMap(MediaTvSeries::getId, s -> s, (l, r) -> l, LinkedHashMap::new));

        // 批量加载 ContentAsset，作为 posterFileId/backdropFileId 的权威来源
        Map<UUID, UUID> moviePosterAssetMap = new LinkedHashMap<>();
        Map<UUID, UUID> movieBackdropAssetMap = new LinkedHashMap<>();
        items.stream().collect(Collectors.groupingBy(MediaVideoItem::getOwnerUserId)).forEach(
                (catalogOwnerUserId, ownedItems) -> loadPrimaryAssets(
                        catalogOwnerUserId,
                        ResourceType.MOVIE.getValue(),
                        ownedItems.stream()
                                .map(MediaVideoItem::getMovieId)
                                .filter(Objects::nonNull)
                                .distinct()
                                .toList(),
                        moviePosterAssetMap,
                        movieBackdropAssetMap
                )
        );
        Map<UUID, UUID> seriesPosterAssetMap = new LinkedHashMap<>();
        Map<UUID, UUID> seriesBackdropAssetMap = new LinkedHashMap<>();
        items.stream().collect(Collectors.groupingBy(MediaVideoItem::getOwnerUserId)).forEach(
                (catalogOwnerUserId, ownedItems) -> loadPrimaryAssets(
                        catalogOwnerUserId,
                        ResourceType.TV_SERIES.getValue(),
                        ownedItems.stream()
                                .map(MediaVideoItem::getSeriesId)
                                .filter(Objects::nonNull)
                                .distinct()
                                .toList(),
                        seriesPosterAssetMap,
                        seriesBackdropAssetMap
                )
        );

        return new BatchIndex(movieMap, episodeMap, seriesMap,
                moviePosterAssetMap, movieBackdropAssetMap,
                seriesPosterAssetMap, seriesBackdropAssetMap,
                loadAvailability(items.stream().map(MediaVideoItem::getFileNodeId).toList()));
    }

    private void loadPrimaryAssets(
            UUID catalogOwnerUserId,
            String resourceType,
            List<UUID> resourceIds,
            Map<UUID, UUID> posterAssetMap,
            Map<UUID, UUID> backdropAssetMap
    ) {
        if (resourceIds.isEmpty()) {
            return;
        }
        List<ContentAsset> assets = contentAssetRepository.listPrimaryAssets(
                catalogOwnerUserId,
                resourceType,
                resourceIds,
                List.of(AssetType.POSTER.getValue(), AssetType.BACKDROP.getValue())
        );
        for (ContentAsset asset : assets) {
            if (asset.getFileNodeId() == null) {
                continue;
            }
            if (AssetType.POSTER.getValue().equals(asset.getAssetType())) {
                posterAssetMap.putIfAbsent(asset.getResourceId(), asset.getFileNodeId());
            } else if (AssetType.BACKDROP.getValue().equals(asset.getAssetType())) {
                backdropAssetMap.putIfAbsent(asset.getResourceId(), asset.getFileNodeId());
            }
        }
    }

    private void putPrimaryAsset(
            UUID catalogOwnerUserId,
            String resourceType,
            UUID resourceId,
            String assetType,
            Map<UUID, UUID> target
    ) {
        contentAssetRepository.findPrimaryAsset(catalogOwnerUserId, resourceType, resourceId, assetType)
                .map(ContentAsset::getFileNodeId)
                .ifPresent(fileNodeId -> target.put(resourceId, fileNodeId));
    }

    private MovieVideoItemDto toVideoDto(UUID requesterUserId, MediaVideoItem item, BatchIndex index) {
        UUID catalogOwnerUserId = item.getOwnerUserId();
        boolean isEpisode = MediaType.EPISODE.getValue().equals(item.getMediaType());

        MediaMovie movie = null;
        MediaTvEpisode episode = null;
        if (!isEpisode && item.getMovieId() != null) {
            movie = index.movieMap().get(item.getMovieId());
        }
        if (isEpisode && item.getEpisodeId() != null) {
            episode = index.episodeMap().get(item.getEpisodeId());
        }

        String title;
        String originalTitle = null;
        LocalDate releaseDate = null;
        String overview = null;
        Integer runtimeSeconds = null;
        Double rating = null;
        Integer voteCount = null;
        String contentRating = null;
        String tagline = null;
        List<String> genres = List.of();
        List<CastMemberDto> castMembers = List.of();
        List<CrewMemberDto> crewMembers = List.of();
        UUID posterFileId = null;
        UUID backdropFileId = null;
        Map<String, Object> metadata = Map.of();

        if (movie != null) {
            title = movie.getTitle();
            originalTitle = movie.getOriginalTitle();
            releaseDate = movie.getReleaseDate();
            overview = movie.getOverview();
            runtimeSeconds = movie.getRuntimeSeconds();
            rating = movie.getRating();
            voteCount = movie.getVoteCount();
            contentRating = movie.getContentRating();
            tagline = movie.getTagline();
            genres = catalogMappers.extractGenreNames(movie.getGenres());
            castMembers = catalogMappers.toCastDtos(catalogOwnerUserId, movie.getCastMembers());
            crewMembers = catalogMappers.toCrewDtos(catalogOwnerUserId, movie.getCrewMembers());
            posterFileId = index.moviePosterAssetMap().get(movie.getId());
            backdropFileId = index.movieBackdropAssetMap().get(movie.getId());
            if (posterFileId == null) {
                posterFileId = movie.getPosterFileId();
            }
            if (backdropFileId == null) {
                backdropFileId = movie.getBackdropFileId();
            }
            metadata = movie.getMetadata();
        } else if (episode != null) {
            // 列表卡片展示作品名（系列名），集标题不作为主标题，避免 Portal/列表显示成集数。
            title = episode.getTitle();
            overview = episode.getOverview();
            runtimeSeconds = episode.getRuntimeSeconds();
            rating = episode.getRating();
            voteCount = episode.getVoteCount();
            metadata = episode.getMetadata();
            // episode 海报从 series 继承（批量加载，无额外查询）
            if (item.getSeriesId() != null) {
                MediaTvSeries series = index.seriesMap().get(item.getSeriesId());
                if (series != null) {
                    posterFileId = index.seriesPosterAssetMap().get(series.getId());
                    backdropFileId = index.seriesBackdropAssetMap().get(series.getId());
                    if (posterFileId == null) {
                        posterFileId = series.getPosterFileId();
                    }
                    if (backdropFileId == null) {
                        backdropFileId = series.getBackdropFileId();
                    }
                    String seriesTitle = series.getTitle();
                    if (seriesTitle != null && !seriesTitle.isBlank()) {
                        title = seriesTitle;
                    } else if (title == null || title.isBlank()) {
                        title = episode.getTitle();
                    }
                    if (genres.isEmpty()) genres = catalogMappers.extractGenreNames(series.getGenres());
                    if (castMembers.isEmpty()) {
                        castMembers = catalogMappers.toCastDtos(catalogOwnerUserId, series.getCastMembers());
                    }
                    if (crewMembers.isEmpty()) {
                        crewMembers = catalogMappers.toCrewDtos(catalogOwnerUserId, series.getCrewMembers());
                    }
                    if (contentRating == null) contentRating = series.getContentRating();
                }
            }
        } else {
            title = "未知";
        }

        MediaPlaybackTokenService.IssuedMediaToken assetToken = null;
        if (item.getLibrarySourceId() != null && (posterFileId != null || backdropFileId != null)) {
            assetToken = mediaPlaybackTokenService.issue(requesterUserId, item.getId());
        }
        String posterUrl = resolveAssetUrl(item, posterFileId, assetToken);
        String backdropUrl = resolveAssetUrl(item, backdropFileId, assetToken);

        return new MovieVideoItemDto(
                item.getId(),
                item.getFileNodeId(),
                item.getMediaType(),
                title,
                originalTitle,
                releaseDate,
                overview,
                posterFileId,
                backdropFileId,
                runtimeSeconds,
                item.getMetadataStatus(),
                item.getNfoStatus(),
                item.getUpdatedAt(),
                metadata,
                posterUrl,
                backdropUrl,
                Map.of(),
                genres,
                castMembers,
                crewMembers,
                rating,
                voteCount,
                contentRating,
                tagline,
                item.getVideoCodec(),
                item.getAudioCodec(),
                item.getContainerFormat(),
                item.getResolutionWidth(),
                item.getResolutionHeight(),
                item.getSeriesId(),
                item.getSeasonId(),
                item.getSeasonNumber(),
                item.getEpisodeNumber(),
                item.getMovieId(),
                item.getEpisodeId(),
                item.getVersionLabel(),
                item.isDefaultVersion(),
                index.availabilityByFileNodeId().getOrDefault(item.getFileNodeId(), "AVAILABLE")
        );
    }

    private MovieLibraryItemDto toLibraryDto(UUID requesterUserId, MediaVideoItem item, BatchIndex index) {
        boolean isEpisode = MediaType.EPISODE.getValue().equals(item.getMediaType());
        MediaMovie movie = item.getMovieId() == null ? null : index.movieMap().get(item.getMovieId());
        MediaTvEpisode episode = item.getEpisodeId() == null ? null : index.episodeMap().get(item.getEpisodeId());
        MediaTvSeries series = item.getSeriesId() == null ? null : index.seriesMap().get(item.getSeriesId());

        String title = "未知";
        String originalTitle = null;
        LocalDate releaseDate = null;
        Integer runtimeSeconds = null;
        List<String> genres = List.of();
        Double rating = null;
        UUID posterFileId = null;

        if (!isEpisode && movie != null) {
            title = movie.getTitle();
            originalTitle = movie.getOriginalTitle();
            releaseDate = movie.getReleaseDate();
            runtimeSeconds = movie.getRuntimeSeconds();
            genres = catalogMappers.extractGenreNames(movie.getGenres());
            rating = movie.getRating();
            posterFileId = index.moviePosterAssetMap().get(movie.getId());
            if (posterFileId == null) {
                posterFileId = movie.getPosterFileId();
            }
        } else if (episode != null) {
            // 列表卡片展示作品名（系列名），与 Portal 瓷砖一致。
            title = episode.getTitle();
            releaseDate = episode.getAirDate();
            runtimeSeconds = episode.getRuntimeSeconds();
            rating = episode.getRating();
            if (series != null) {
                String seriesTitle = series.getTitle();
                if (seriesTitle != null && !seriesTitle.isBlank()) {
                    title = seriesTitle;
                }
                genres = catalogMappers.extractGenreNames(series.getGenres());
                posterFileId = index.seriesPosterAssetMap().get(series.getId());
                if (posterFileId == null) {
                    posterFileId = series.getPosterFileId();
                }
            }
        }

        MediaPlaybackTokenService.IssuedMediaToken assetToken = null;
        if (item.getLibrarySourceId() != null && posterFileId != null) {
            assetToken = mediaPlaybackTokenService.issue(requesterUserId, item.getId());
        }
        return new MovieLibraryItemDto(
                item.getId(),
                item.getFileNodeId(),
                item.getMediaType(),
                title,
                originalTitle,
                releaseDate,
                posterFileId,
                runtimeSeconds,
                item.getMetadataStatus(),
                item.getUpdatedAt(),
                resolveAssetUrl(item, posterFileId, assetToken),
                genres,
                rating,
                item.getSeriesId(),
                item.getSeasonNumber(),
                item.getEpisodeNumber(),
                index.availabilityByFileNodeId().getOrDefault(item.getFileNodeId(), "AVAILABLE")
        );
    }

    private Map<UUID, String> loadAvailability(List<UUID> fileNodeIds) {
        List<UUID> distinctIds = fileNodeIds.stream().filter(Objects::nonNull).distinct().toList();
        if (distinctIds.isEmpty()) {
            return Map.of();
        }
        return fileContentAvailabilityQueryService.findAvailabilityByFileNodeIds(distinctIds);
    }


    private String resolveAssetUrl(
            MediaVideoItem item,
            UUID fileNodeId,
            MediaPlaybackTokenService.IssuedMediaToken token
    ) {
        if (fileNodeId == null) {
            return null;
        }
        if (item.getLibrarySourceId() == null) {
            return catalogMappers.resolveFileUrl(item.getOwnerUserId(), fileNodeId);
        }
        return "/api/v1/public/video/items/" + item.getId()
                + "/assets/" + fileNodeId + "?token=" + token.token();
    }



    /**
     * 解析演员头像 URL：优先使用 MinIO（profileFileId），降级到 TMDB（profilePath）。
     */

}
