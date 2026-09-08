package com.omninest.modules.video.service;

import com.omninest.common.api.PageResponse;
import com.omninest.common.cache.ReadThroughCache;
import com.omninest.modules.media.domain.AssetType;
import com.omninest.common.enums.ErrorCode;
import com.omninest.modules.media.domain.MetadataStatus;
import com.omninest.modules.video.domain.MediaType;
import com.omninest.modules.media.domain.ResourceType;
import com.omninest.common.error.BusinessException;
import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncScope;
import com.omninest.modules.media.domain.MediaPlaybackProgress;
import com.omninest.modules.media.domain.MediaPlaybackType;
import com.omninest.modules.media.service.MediaPlaybackProgressService;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.video.domain.MediaMovie;
import com.omninest.modules.video.domain.MediaSeriesFavorite;
import com.omninest.modules.video.domain.MediaTvEpisode;
import com.omninest.modules.video.domain.MediaTvSeason;
import com.omninest.modules.video.domain.MediaTvSeries;
import com.omninest.modules.video.domain.MediaVideoItem;
import com.omninest.modules.file.service.FileDeletionService;
import com.omninest.modules.file.service.FilePurgeOrigin;
import com.omninest.modules.file.service.FileQueryService;
import com.omninest.modules.video.dto.MovieDtos.CastMemberDto;
import com.omninest.modules.video.dto.MovieDtos.CrewMemberDto;
import com.omninest.modules.video.dto.MovieDtos.MovieContinueWatchingDto;
import com.omninest.modules.video.dto.MovieDtos.MovieContentAssetDto;
import com.omninest.modules.video.dto.MovieDtos.MovieDashboardDto;
import com.omninest.modules.video.dto.MovieDtos.MovieLibraryItemDto;
import com.omninest.modules.video.dto.MovieDtos.MovieMetadataUpdateRequest;
import com.omninest.modules.video.dto.MovieDtos.MovieSeasonDto;
import com.omninest.modules.video.dto.MovieDtos.MovieSeasonDetailDto;
import com.omninest.modules.video.dto.MovieDtos.MovieSeriesDetailDto;
import com.omninest.modules.video.dto.MovieDtos.MovieSeriesDto;
import com.omninest.modules.video.dto.MovieDtos.UpdateSeriesMetadataRequest;
import com.omninest.modules.video.dto.MovieDtos.MovieStatsDto;
import com.omninest.modules.video.dto.MovieDtos.MovieVideoItemDto;
import com.omninest.modules.video.repository.MediaMovieRepository;
import com.omninest.modules.video.repository.MediaSeriesFavoriteRepository;
import com.omninest.modules.video.repository.MediaTvEpisodeRepository;
import com.omninest.modules.video.repository.MediaTvSeasonRepository;
import com.omninest.modules.video.repository.MediaTvSeriesRepository;
import com.omninest.modules.video.repository.MediaVideoCollectionRepository;
import com.omninest.modules.video.repository.MediaVideoFavoriteRepository;
import com.omninest.modules.video.repository.MediaVideoItemRepository;
import com.omninest.modules.video.repository.MediaWatchHistoryRepository;
import java.time.Duration;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Objects;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Sort;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 影视库聚合查询与条目维护服务。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class MovieLibraryService {
    private final MediaVideoItemRepository videoItemRepository;
    private final MediaTvSeriesRepository tvSeriesRepository;
    private final MediaTvSeasonRepository tvSeasonRepository;
    private final MediaPlaybackProgressService progressService;
    private final FileDeletionService fileDeletionService;
    private final FileQueryService fileQueryService;
    private final VideoCatalogMappers catalogMappers;
    private final ContentAssetService contentAssetService;
    private final MediaMovieRepository movieRepository;
    private final MediaTvEpisodeRepository episodeRepository;
    private final VideoItemDtoConverter videoItemDtoConverter;
    private final ReadThroughCache readThroughCache;
    private final MediaSyncEventService syncEventService;
    private final MediaLibraryAccessService mediaLibraryAccessService;
    private final MediaContentAccessService mediaContentAccessService;
    private final MediaSeriesFavoriteRepository seriesFavoriteRepository;
    private final MediaPlaybackTokenService mediaPlaybackTokenService;
    private final MediaVideoFavoriteRepository videoFavoriteRepository;
    private final MediaWatchHistoryRepository watchHistoryRepository;
    private final MediaVideoCollectionRepository videoCollectionRepository;

    @Transactional(readOnly = true)
    public MovieDashboardDto dashboard(UUID ownerUserId) {
        String cacheKey = "omninest:dashboard:video:" + ownerUserId;
        return readThroughCache.getOrLoad(cacheKey, Duration.ofMinutes(3),
                () -> loadDashboard(ownerUserId),
                MovieDashboardDto.class);
    }

    /**
     * 从数据库加载视频仪表盘数据。
     */
    private MovieDashboardDto loadDashboard(UUID ownerUserId) {
        Set<UUID> readableLibraryIds = mediaLibraryAccessService.findReadableLibraryIds(ownerUserId);
        MovieStatsDto stats = new MovieStatsDto(
                videoItemRepository.countReadableOriginalsByMediaType(
                        ownerUserId, readableLibraryIds, MediaType.MOVIE.getValue()),
                videoItemRepository.countReadableOriginalsByMediaType(
                        ownerUserId, readableLibraryIds, MediaType.EPISODE.getValue()),
                videoItemRepository.countReadableOriginalSeries(ownerUserId, readableLibraryIds),
                videoItemRepository.countReadableOriginalsByMetadataStatus(
                        ownerUserId, readableLibraryIds, MetadataStatus.FAILED.getValue()),
                videoFavoriteRepository.countByOwnerUserId(ownerUserId)
                        + seriesFavoriteRepository.countByOwnerUserId(ownerUserId),
                watchHistoryRepository.countByOwnerUserId(ownerUserId),
                videoCollectionRepository.countByOwnerUserId(ownerUserId),
                progressService.countIncomplete(ownerUserId, MediaPlaybackType.VIDEO)
        );
        PageRequest recentPage = PageRequest.of(
                0,
                48,
                Sort.by(Sort.Direction.DESC, "updatedAt").and(Sort.by(Sort.Direction.DESC, "id"))
        );
        List<MediaVideoItem> recentItems = deduplicateBySeries(
                videoItemRepository.findReadableOriginals(ownerUserId, readableLibraryIds, recentPage).getContent()
        ).stream().limit(12).toList();
        List<MovieVideoItemDto> recentlyAdded = videoItemDtoConverter.toVideoDtos(ownerUserId, recentItems);
        List<MediaPlaybackProgress> progresses = progressService.latest(ownerUserId, MediaPlaybackType.VIDEO);
        List<MovieContinueWatchingDto> continueWatching = toContinueWatchingDtos(ownerUserId, progresses);
        return new MovieDashboardDto(stats, recentlyAdded, continueWatching, List.of());
    }

    @Transactional(readOnly = true)
    public List<MovieVideoItemDto> movies(UUID ownerUserId) {
        Set<UUID> readableLibraryIds = mediaLibraryAccessService.findReadableLibraryIds(ownerUserId);
        return videoItemDtoConverter.toVideoDtos(
                ownerUserId,
                videoItemRepository.findReadableOriginalsByMediaType(
                        ownerUserId,
                        readableLibraryIds,
                        MediaType.MOVIE.getValue()
                )
        );
    }

    /**
     * 分页读取影视库卡片数据。
     *
     * @param ownerUserId 当前用户 ID
     * @param mediaType 媒体类型
     * @param metadataStatus 可选元数据状态
     * @param page 页码
     * @param size 每页大小
     * @param sort 排序表达式
     * @return 有界的轻量影视条目页
     */
    @Transactional(readOnly = true)
    public PageResponse<MovieLibraryItemDto> libraryPage(
            UUID ownerUserId,
            String mediaType,
            String metadataStatus,
            int page,
            int size,
            String sort
    ) {
        String normalizedMediaType = normalizeLibraryMediaType(mediaType);
        String normalizedStatus = normalizeLibraryMetadataStatus(metadataStatus);
        PageRequest pageable = createLibraryPageRequest(page, size, sort);
        Set<UUID> readableLibraryIds = mediaLibraryAccessService.findReadableLibraryIds(ownerUserId);
        Page<MediaVideoItem> result = videoItemRepository.findReadableOriginalsByMediaType(
                ownerUserId,
                readableLibraryIds,
                normalizedMediaType,
                normalizedStatus,
                pageable
        );
        return PageResponse.of(
                videoItemDtoConverter.toLibraryDtos(ownerUserId, result.getContent()),
                result.getNumber(),
                result.getSize(),
                result.getTotalElements()
        );
    }

    @Transactional(readOnly = true)
    public List<MovieVideoItemDto> episodes(UUID ownerUserId) {
        Set<UUID> readableLibraryIds = mediaLibraryAccessService.findReadableLibraryIds(ownerUserId);
        List<MediaVideoItem> items = deduplicateBySeries(
                videoItemRepository.findReadableOriginalsByMediaType(
                        ownerUserId,
                        readableLibraryIds,
                        MediaType.EPISODE.getValue()
                ));
        return videoItemDtoConverter.toVideoDtos(ownerUserId, items);
    }

    private String normalizeLibraryMediaType(String mediaType) {
        if (mediaType != null
                && (MediaType.EPISODE.getValue().equalsIgnoreCase(mediaType)
                || "TVSHOW".equalsIgnoreCase(mediaType))) {
            return MediaType.EPISODE.getValue();
        }
        return MediaType.MOVIE.getValue();
    }

    private String normalizeLibraryMetadataStatus(String metadataStatus) {
        if (metadataStatus == null || metadataStatus.isBlank() || "ALL".equalsIgnoreCase(metadataStatus)) {
            return null;
        }
        try {
            return MetadataStatus.fromValue(metadataStatus).getValue();
        } catch (IllegalArgumentException exception) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "未知的元数据状态");
        }
    }

    private PageRequest createLibraryPageRequest(int page, int size, String sortExpression) {
        int safePage = Math.max(page, 0);
        int safeSize = Math.min(Math.max(size, 12), 100);
        String[] sortParts = sortExpression == null ? new String[0] : sortExpression.split(",", 2);
        String sortField = switch (sortParts.length == 0 ? "" : sortParts[0]) {
            case "createdAt" -> "createdAt";
            case "metadataStatus" -> "metadataStatus";
            default -> "updatedAt";
        };
        Sort.Direction direction = sortParts.length > 1 && "asc".equalsIgnoreCase(sortParts[1])
                ? Sort.Direction.ASC
                : Sort.Direction.DESC;
        Sort sort = Sort.by(direction, sortField).and(Sort.by(direction, "id"));
        return PageRequest.of(safePage, safeSize, sort);
    }

    @Transactional(readOnly = true)
    public List<MovieSeriesDto> seriesByType(UUID ownerUserId, String seriesType) {
        Set<UUID> readableLibraryIds = mediaLibraryAccessService.findReadableLibraryIds(ownerUserId);
        List<MediaTvSeries> items = tvSeriesRepository
                .findActiveReadableBySeriesType(ownerUserId, readableLibraryIds, seriesType);
        return toSeriesDtos(ownerUserId, items);
    }

    /**
     * 查询当前用户收藏的系列（剧集与动漫），按收藏时间倒序。
     *
     * @param ownerUserId 所有者用户 ID
     * @return 收藏的系列列表
     */
    @Transactional(readOnly = true)
    public List<MovieSeriesDto> favoriteSeries(UUID ownerUserId) {
        List<MediaSeriesFavorite> favorites =
                seriesFavoriteRepository.findByOwnerUserIdOrderByCreatedAtDesc(ownerUserId);
        if (favorites.isEmpty()) {
            return List.of();
        }
        List<UUID> seriesIds = favorites.stream().map(MediaSeriesFavorite::getSeriesId).toList();
        Set<UUID> readableLibraryIds = mediaLibraryAccessService.findReadableLibraryIds(ownerUserId);
        Map<UUID, MediaTvSeries> seriesIndex = tvSeriesRepository
                .findActiveReadableByIdIn(seriesIds, ownerUserId, readableLibraryIds)
                .stream()
                .collect(Collectors.toMap(
                        MediaTvSeries::getId,
                        series -> series,
                        (left, right) -> left,
                        LinkedHashMap::new
                ));
        List<MediaTvSeries> series = favorites.stream()
                .map(favorite -> seriesIndex.get(favorite.getSeriesId()))
                .filter(Objects::nonNull)
                .toList();
        return toSeriesDtos(ownerUserId, series);
    }

    /**
     * 手动更新系列标题与简介。
     *
     * @param ownerUserId 当前用户 ID
     * @param seriesId 系列 ID
     * @param request 更新请求
     * @return 更新后的系列
     */
    @Transactional(rollbackFor = Exception.class)
    public MovieSeriesDto updateSeriesMetadata(
            UUID ownerUserId,
            UUID seriesId,
            UpdateSeriesMetadataRequest request
    ) {
        MediaTvSeries series = mediaContentAccessService.requireReadableSeries(ownerUserId, seriesId);
        String title = request.title() == null ? "" : request.title().trim();
        if (title.isEmpty()) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "剧集标题不能为空");
        }
        series.setTitle(title);
        if (request.overview() != null) {
            series.setOverview(request.overview());
        }
        series.setUpdatedAt(Instant.now());
        tvSeriesRepository.save(series);
        syncEventService.record(
                ownerUserId,
                SyncScope.VIDEO,
                "VIDEO_SERIES",
                seriesId.toString(),
                SyncAction.UPDATED,
                series.getVersion(),
                Map.of("manualEdited", true)
        );
        return toSeriesDtos(ownerUserId, List.of(series)).getFirst();
    }

    @Transactional(readOnly = true)
    public List<MovieVideoItemDto> recent(UUID ownerUserId, int days) {
        int safeDays = days <= 0 ? 30 : Math.min(days, 365);
        Instant since = Instant.now().minus(safeDays, ChronoUnit.DAYS);
        Set<UUID> readableLibraryIds = mediaLibraryAccessService.findReadableLibraryIds(ownerUserId);
        List<MediaVideoItem> items = deduplicateBySeries(videoItemRepository.findReadableOriginalsUpdatedAfter(
                ownerUserId,
                readableLibraryIds,
                since
        ));
        return videoItemDtoConverter.toVideoDtos(ownerUserId, items);
    }

    @Transactional(readOnly = true)
    public List<MovieContinueWatchingDto> continueWatching(UUID ownerUserId) {
        List<MediaPlaybackProgress> progresses = progressService.latest(ownerUserId, MediaPlaybackType.VIDEO)
                .stream()
                .filter(p -> !p.isCompleted())
                .toList();
        return toContinueWatchingDtos(ownerUserId, progresses);
    }

    @Transactional(readOnly = true)
    public List<MovieVideoItemDto> versions(UUID ownerUserId, UUID videoItemId) {
        MediaVideoItem item = mediaContentAccessService.requireReadableVideo(ownerUserId, videoItemId);
        UUID catalogOwnerUserId = item.getOwnerUserId();
        // 仅返回原始版本（排除派生版本如 AUDIO_ONLY、H265），避免污染分辨率版本切换
        List<MediaVideoItem> allVersions;
        if (item.getMovieId() != null) {
            allVersions = videoItemRepository.findOriginalsByOwnerUserIdAndMovieId(
                    catalogOwnerUserId,
                    item.getMovieId()
            );
        } else if (item.getEpisodeId() != null) {
            allVersions = videoItemRepository.findOriginalsByOwnerUserIdAndEpisodeId(
                    catalogOwnerUserId,
                    item.getEpisodeId()
            );
        } else {
            allVersions = List.of(item);
        }
        return videoItemDtoConverter.toVideoDtos(ownerUserId, allVersions);
    }

    @Transactional(readOnly = true)
    public List<MovieVideoItemDto> episodes(UUID ownerUserId, UUID seriesId) {
        Set<UUID> readableLibraryIds = mediaLibraryAccessService.findReadableLibraryIds(ownerUserId);
        List<MediaVideoItem> items = videoItemRepository.findReadableBySeriesId(
                ownerUserId,
                readableLibraryIds,
                seriesId
        );
        if (items.isEmpty()) {
            throw new BusinessException(ErrorCode.MEDIA_NOT_FOUND, "剧集不存在");
        }
        return videoItemDtoConverter.toVideoDtos(ownerUserId, items);
    }

    @Transactional(readOnly = true)
    public MovieVideoItemDto detail(UUID ownerUserId, UUID videoItemId) {
        MediaVideoItem item = mediaContentAccessService.requireReadableVideo(ownerUserId, videoItemId);
        return videoItemDtoConverter.toVideoDto(ownerUserId, item);
    }

    @Transactional(rollbackFor = Exception.class)
    public MovieVideoItemDto updateMetadata(UUID ownerUserId, UUID videoItemId, MovieMetadataUpdateRequest request) {
        MediaVideoItem item = videoItemRepository.findByIdAndOwnerUserId(videoItemId, ownerUserId)
                .orElseThrow(() -> new BusinessException(
                        ErrorCode.MEDIA_NOT_FOUND,
                        "媒体资源不存在"
                ));
        if (request.title() == null || request.title().isBlank()) {
            throw new BusinessException(
                    ErrorCode.PARAM_ERROR,
                    "标题不能为空"
            );
        }
        // 元数据更新写入逻辑 entity
        String newStatus = normalizeMetadataStatus(request.metadataStatus());
        if (item.getMovieId() != null) {
            MediaMovie movie = movieRepository.findById(item.getMovieId()).orElse(null);
            if (movie != null) {
                movie.setTitle(request.title().trim());
                movie.setOriginalTitle(blankToNull(request.originalTitle()));
                movie.setReleaseDate(request.releaseDate());
                movie.setOverview(blankToNull(request.overview()));
                if (request.posterFileId() != null) {
                    UUID posterFileId = contentAssetService.setPrimaryFileAsset(
                            ownerUserId,
                            movie.getId(),
                            ResourceType.MOVIE.getValue(),
                            AssetType.POSTER.getValue(),
                            request.posterFileId());
                    movie.setPosterFileId(posterFileId);
                }
                if (request.backdropFileId() != null) {
                    UUID backdropFileId = contentAssetService.setPrimaryFileAsset(
                            ownerUserId,
                            movie.getId(),
                            ResourceType.MOVIE.getValue(),
                            AssetType.BACKDROP.getValue(),
                            request.backdropFileId());
                    movie.setBackdropFileId(backdropFileId);
                }
                if (request.runtimeSeconds() != null && request.runtimeSeconds() > 0) {
                    movie.setRuntimeSeconds(request.runtimeSeconds());
                }
                movie.setMetadataStatus(newStatus);
                Map<String, Object> metadata = movie.getMetadata() == null ? new LinkedHashMap<>() : new LinkedHashMap<>(movie.getMetadata());
                metadata.put("manualEdited", true);
                metadata.put("manualEditedAt", Instant.now().toString());
                movie.setMetadata(metadata);
                movieRepository.save(movie);
            }
        } else if (item.getEpisodeId() != null) {
            MediaTvEpisode episode = episodeRepository.findById(item.getEpisodeId()).orElse(null);
            if (episode != null) {
                episode.setTitle(request.title().trim());
                episode.setOverview(blankToNull(request.overview()));
                if (request.runtimeSeconds() != null && request.runtimeSeconds() > 0) {
                    episode.setRuntimeSeconds(request.runtimeSeconds());
                }
                episode.setMetadataStatus(newStatus);
                Map<String, Object> metadata = episode.getMetadata() == null ? new LinkedHashMap<>() : new LinkedHashMap<>(episode.getMetadata());
                metadata.put("manualEdited", true);
                metadata.put("manualEditedAt", Instant.now().toString());
                episode.setMetadata(metadata);
                episodeRepository.save(episode);
            }
        }
        // 同步 metadataStatus 到 VideoItem 本身
        item.setMetadataStatus(newStatus);
        videoItemRepository.save(item);
        recordVideoEvent(ownerUserId, item, SyncAction.UPDATED);
        invalidateDashboardCache(ownerUserId);
        return videoItemDtoConverter.toVideoDto(ownerUserId, item);
    }

    /**
     * 失效指定用户的视频仪表盘缓存。
     *
     * @param ownerUserId 所有者用户 ID
     */
    private void invalidateDashboardCache(UUID ownerUserId) {
        readThroughCache.invalidate("omninest:dashboard:video:" + ownerUserId);
    }

    @Transactional(rollbackFor = Exception.class)
    public UUID deleteItem(UUID ownerUserId, UUID videoItemId) {
        return deleteItem(ownerUserId, videoItemId, false);
    }

    /**
     * 创建视频永久删除任务。
     *
     * @param ownerUserId 所有者用户 ID
     * @param videoItemId 视频条目 ID
     * @param cascade 是否允许级联清理其他业务引用
     * @return 任务 ID
     */
    @Transactional(rollbackFor = Exception.class)
    public UUID deleteItem(UUID ownerUserId, UUID videoItemId, boolean cascade) {
        MediaVideoItem item = videoItemRepository.findByIdAndOwnerUserId(videoItemId, ownerUserId)
                .orElseThrow(() -> new BusinessException(
                        ErrorCode.MEDIA_NOT_FOUND,
                        "媒体资源不存在"
                ));
        UUID taskId = fileDeletionService.deletePermanently(
                ownerUserId,
                item.getFileNodeId(),
                cascade,
                new FilePurgeOrigin("MOVIES", videoItemId),
                null
        );
        log.info("视频永久删除任务已创建: taskId={}, videoItemId={}, userId={}",
                taskId, videoItemId, ownerUserId);
        return taskId;
    }

    private void recordVideoEvent(UUID ownerUserId, MediaVideoItem item, SyncAction action) {
        syncEventService.record(
                ownerUserId,
                SyncScope.VIDEO,
                "VIDEO_ITEM",
                item.getId().toString(),
                action,
                item.getVersion(),
                Map.of()
        );
    }

    private List<MovieContinueWatchingDto> toContinueWatchingDtos(UUID ownerUserId, List<MediaPlaybackProgress> progresses) {
        if (progresses.isEmpty()) {
            return List.of();
        }
        Map<MediaPlaybackProgress, UUID> progressItemIds = progresses.stream()
                .map(progress -> Map.entry(progress, parseVideoItemId(progress.getMediaKey())))
                .filter(entry -> entry.getValue() != null)
                .collect(Collectors.toMap(
                        Map.Entry::getKey,
                        Map.Entry::getValue,
                        (left, right) -> left,
                        LinkedHashMap::new
        ));
        List<UUID> videoItemIds = progressItemIds.values().stream().distinct().toList();
        Set<UUID> readableLibraryIds = mediaLibraryAccessService.findReadableLibraryIds(ownerUserId);
        List<MediaVideoItem> items = videoItemRepository.findReadableByIds(
                ownerUserId,
                readableLibraryIds,
                videoItemIds
        );
        Map<UUID, MovieVideoItemDto> itemIndex = videoItemDtoConverter.toVideoDtos(ownerUserId, items).stream()
                .collect(Collectors.toMap(
                        MovieVideoItemDto::id,
                        item -> item,
                        (left, right) -> left,
                        LinkedHashMap::new
                ));

        return progressItemIds.entrySet().stream()
                .flatMap(entry -> Optional.ofNullable(itemIndex.get(entry.getValue()))
                        .map(item -> {
                            MediaPlaybackProgress progress = entry.getKey();
                            return new MovieContinueWatchingDto(
                                    item.id(),
                                    item.title(),
                                    item.posterFileId(),
                                    item.posterUrl(),
                                    progress.getPositionSeconds(),
                                    progress.getDurationSeconds(),
                                    progressPercent(progress),
                                    progress.getUpdatedAt()
                            );
                        })
                        .stream())
                .toList();
    }

    private UUID parseVideoItemId(String mediaKey) {
        try {
            return UUID.fromString(mediaKey);
        } catch (IllegalArgumentException exception) {
            log.warn("忽略无效的视频进度键: mediaKey={}", mediaKey);
            return null;
        }
    }

    private double progressPercent(MediaPlaybackProgress progress) {
        if (progress.getDurationSeconds() <= 0) {
            return 0;
        }
        double value = progress.getPositionSeconds() * 100.0 / progress.getDurationSeconds();
        return Math.round(value * 100.0) / 100.0;
    }

    private String blankToNull(String value) {
        if (value == null || value.isBlank()) {
            return null;
        }
        return value.trim();
    }

    private String normalizeMetadataStatus(String value) {
        if (value == null || value.isBlank()) {
            return "MANUAL";
        }
        String normalized = value.trim().toUpperCase(Locale.ROOT);
        return switch (normalized) {
            case "PENDING", "MATCHED", "MANUAL", "FAILED" -> normalized;
            default -> MetadataStatus.MANUAL.getValue();
        };
    }




    private List<MovieSeriesDto> toSeriesDtos(UUID ownerUserId, List<MediaTvSeries> items) {
        if (items.isEmpty()) {
            return List.of();
        }
        Map<UUID, Map<String, MovieContentAssetDto>> assets = new LinkedHashMap<>();
        items.stream().collect(Collectors.groupingBy(MediaTvSeries::getOwnerUserId)).forEach(
                (catalogOwnerUserId, ownedSeries) -> assets.putAll(contentAssetService.primarySeriesAssets(
                        catalogOwnerUserId,
                        ownedSeries.stream().map(MediaTvSeries::getId).toList()
                ))
        );
        Set<UUID> favoriteSeriesIds = seriesFavoriteRepository.findByOwnerUserIdAndSeriesIdIn(
                        ownerUserId,
                        items.stream().map(MediaTvSeries::getId).toList()
                ).stream()
                .map(favorite -> favorite.getSeriesId())
                .collect(Collectors.toUnmodifiableSet());
        return items.stream()
                .map(item -> toSeriesDto(
                        ownerUserId,
                        item.getOwnerUserId(),
                        item,
                        assets.getOrDefault(item.getId(), Map.of()),
                        favoriteSeriesIds.contains(item.getId())
                ))
                .toList();
    }

    private MovieSeriesDto toSeriesDto(
            UUID requesterUserId,
            UUID catalogOwnerUserId,
            MediaTvSeries item,
            Map<String, MovieContentAssetDto> assets,
            boolean favorite
    ) {
        Map<String, MovieContentAssetDto> safeAssets = protectSeriesAssets(requesterUserId, item, assets);
        String resolvedPosterUrl = posterUrl(safeAssets);
        String resolvedBackdropUrl = backdropUrl(safeAssets);
        return new MovieSeriesDto(
                item.getId(),
                item.getTitle(),
                item.getOriginalTitle(),
                item.getFirstAirDate(),
                item.getOverview(),
                item.getPosterFileId(),
                item.getBackdropFileId(),
                item.getMetadataStatus(),
                item.getUpdatedAt(),
                item.getMetadata(),
                resolvedPosterUrl,
                resolvedBackdropUrl,
                safeAssets,
                catalogMappers.extractGenreNames(item.getGenres()),
                catalogMappers.toCastDtos(catalogOwnerUserId, item.getCastMembers()),
                catalogMappers.toCrewDtos(catalogOwnerUserId, item.getCrewMembers()),
                item.getRating(),
                item.getVoteCount(),
                item.getContentRating(),
                item.getSeriesType(),
                favorite
        );
    }

    private MovieSeasonDto toSeasonDto(UUID ownerUserId, MediaTvSeason season) {
        String posterUrl = null;
        if (season.getPosterFileId() != null) {
            posterUrl = catalogMappers.resolveFileUrl(ownerUserId, season.getPosterFileId());
        }
        return new MovieSeasonDto(
                season.getId(),
                season.getSeasonNumber(),
                season.getTitle(),
                season.getOverview(),
                season.getAirDate(),
                season.getEpisodeCount(),
                season.getPosterFileId(),
                season.getRating(),
                posterUrl
        );
    }

    @Transactional(readOnly = true)
    public MovieSeriesDetailDto seriesDetail(UUID ownerUserId, UUID seriesId) {
        Set<UUID> readableLibraryIds = mediaLibraryAccessService.findReadableLibraryIds(ownerUserId);
        MediaTvSeries series = tvSeriesRepository.findActiveReadableById(
                        seriesId,
                        ownerUserId,
                        readableLibraryIds
                )
                .orElseThrow(() -> new BusinessException(
                        ErrorCode.MEDIA_NOT_FOUND,
                        "剧集不存在"
                ));
        UUID catalogOwnerUserId = series.getOwnerUserId();
        Map<String, MovieContentAssetDto> seriesAssets = contentAssetService
                .primarySeriesAssets(catalogOwnerUserId, List.of(seriesId))
                .getOrDefault(seriesId, Map.of());
        boolean favorite = seriesFavoriteRepository.existsByOwnerUserIdAndSeriesId(ownerUserId, seriesId);
        MovieSeriesDto seriesDto = toSeriesDto(
                ownerUserId,
                catalogOwnerUserId,
                series,
                seriesAssets,
                favorite
        );
        List<MediaTvSeason> seasons = tvSeasonRepository
                .findByOwnerUserIdAndSeriesIdOrderBySeasonNumberAsc(catalogOwnerUserId, seriesId);
        List<MovieSeasonDto> seasonDtos = seasons.stream()
                .map(season -> toSeasonDto(catalogOwnerUserId, season))
                .toList();
        return new MovieSeriesDetailDto(seriesDto, seasonDtos, seriesDto.castMembers(), seriesDto.crewMembers());
    }

    @Transactional(readOnly = true)
    public MovieSeasonDetailDto seasonDetail(UUID ownerUserId, UUID seriesId, int seasonNumber) {
        Set<UUID> readableLibraryIds = mediaLibraryAccessService.findReadableLibraryIds(ownerUserId);
        MediaTvSeries series = tvSeriesRepository.findActiveReadableById(
                        seriesId,
                        ownerUserId,
                        readableLibraryIds
                )
                .orElseThrow(() -> new BusinessException(ErrorCode.MEDIA_NOT_FOUND, "剧集不存在"));
        UUID catalogOwnerUserId = series.getOwnerUserId();
        MediaTvSeason season = tvSeasonRepository.findByOwnerUserIdAndSeriesIdAndSeasonNumber(
                        catalogOwnerUserId,
                        seriesId,
                        seasonNumber
                )
                .orElseThrow(() -> new BusinessException(
                        ErrorCode.MEDIA_NOT_FOUND,
                        "季信息不存在"
                ));
        MovieSeasonDto seasonDto = toSeasonDto(catalogOwnerUserId, season);
        List<MediaVideoItem> episodes = videoItemRepository
                .findReadableBySeriesIdAndSeasonNumber(
                        ownerUserId,
                        readableLibraryIds,
                        seriesId,
                        seasonNumber
                );
        List<MovieVideoItemDto> episodeDtos = videoItemDtoConverter.toVideoDtos(ownerUserId, episodes);
        return new MovieSeasonDetailDto(seasonDto, episodeDtos);
    }

    @Transactional(readOnly = true)
    public List<MovieContentAssetDto> itemAssets(UUID ownerUserId, UUID videoItemId) {
        MediaVideoItem item = mediaContentAccessService.requireReadableVideo(ownerUserId, videoItemId);
        List<MovieContentAssetDto> assets = contentAssetService.allVideoAssets(item.getOwnerUserId(), videoItemId);
        if (item.getLibrarySourceId() == null || assets.isEmpty()) {
            return assets;
        }
        MediaPlaybackTokenService.IssuedMediaToken token = mediaPlaybackTokenService.issue(ownerUserId, videoItemId);
        return assets.stream().map(asset -> {
            String url = asset.fileNodeId() == null ? null
                    : "/api/v1/public/video/items/" + videoItemId
                    + "/assets/" + asset.fileNodeId() + "?token=" + token.token();
            return new MovieContentAssetDto(
                    asset.id(),
                    asset.assetType(),
                    asset.fileNodeId(),
                    url,
                    asset.provider(),
                    asset.language(),
                    asset.primary(),
                    asset.metadata()
            );
        }).toList();
    }

    private String posterUrl(Map<String, MovieContentAssetDto> assets) {
        return Optional.ofNullable(assets)
                .map(a -> a.get(AssetType.POSTER.getValue()))
                .map(MovieContentAssetDto::url)
                .orElse(null);
    }

    private String backdropUrl(Map<String, MovieContentAssetDto> assets) {
        return Optional.ofNullable(assets)
                .map(a -> a.get(AssetType.BACKDROP.getValue()))
                .map(MovieContentAssetDto::url)
                .orElse(null);
    }

    private Map<String, MovieContentAssetDto> safeAssets(Map<String, MovieContentAssetDto> assets) {
        return assets == null ? Map.of() : assets;
    }

    private Map<String, MovieContentAssetDto> protectSeriesAssets(
            UUID requesterUserId,
            MediaTvSeries series,
            Map<String, MovieContentAssetDto> assets
    ) {
        Map<String, MovieContentAssetDto> safe = safeAssets(assets);
        if (series.getLibrarySourceId() == null || safe.isEmpty()) {
            return safe;
        }
        MediaPlaybackTokenService.IssuedMediaToken token = mediaPlaybackTokenService.issueSeries(
                requesterUserId,
                series.getId()
        );
        return safe.entrySet().stream().collect(Collectors.toUnmodifiableMap(
                Map.Entry::getKey,
                entry -> {
                    MovieContentAssetDto asset = entry.getValue();
                    String url = asset.fileNodeId() == null ? null
                            : "/api/v1/public/video/series/" + series.getId()
                            + "/assets/" + asset.fileNodeId() + "?token=" + token.token();
                    return new MovieContentAssetDto(
                            asset.id(),
                            asset.assetType(),
                            asset.fileNodeId(),
                            url,
                            asset.provider(),
                            asset.language(),
                            asset.primary(),
                            asset.metadata()
                    );
                }
        ));
    }

    /**
     * 按系列去重：同系列只保留最新更新的一集，独立电影不去重。
     * items 需已按 updatedAt 降序排列。
     * seriesId 在文件入库时即已设置，因此无需额外兜底策略。
     */
    private List<MediaVideoItem> deduplicateBySeries(List<MediaVideoItem> items) {
        Set<UUID> seenSeriesIds = new HashSet<>();
        return items.stream().filter(item -> {
            UUID seriesId = item.getSeriesId();
            if (seriesId != null) {
                return seenSeriesIds.add(seriesId);
            }
            return true;
        }).toList();
    }

}
