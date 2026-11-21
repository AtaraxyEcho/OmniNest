package com.omninest.modules.video.service;

import com.omninest.common.api.PageClamps;
import com.omninest.common.api.PageResponse;
import com.omninest.common.cache.ReadThroughCache;
import com.omninest.common.enums.CollectionType;
import com.omninest.modules.media.domain.AssetType;
import com.omninest.common.enums.ErrorCode;
import com.omninest.modules.media.domain.MetadataStatus;
import com.omninest.modules.video.domain.MediaType;
import com.omninest.modules.media.domain.ResourceType;
import com.omninest.common.error.BusinessException;
import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncScope;
import com.omninest.common.util.LikePatterns;
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
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.service.FileDeletionService;
import com.omninest.modules.file.service.FilePurgeOrigin;
import com.omninest.modules.file.service.FileQueryService;
import com.omninest.modules.file.service.DerivedAssetStorageService;
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
import com.omninest.modules.video.dto.MovieDtos.VideoPosterUploadDto;
import com.omninest.modules.video.repository.MediaMovieRepository;
import com.omninest.modules.video.repository.MediaSeriesFavoriteRepository;
import com.omninest.modules.video.repository.MediaTvEpisodeRepository;
import com.omninest.modules.video.repository.MediaTvSeasonRepository;
import com.omninest.modules.video.repository.MediaTvSeriesRepository;
import com.omninest.modules.video.repository.MediaVideoCollectionRepository;
import com.omninest.modules.video.repository.MediaVideoFavoriteRepository;
import com.omninest.modules.video.repository.MediaVideoItemRepository;
import com.omninest.modules.video.repository.MediaWatchHistoryRepository;
import java.io.IOException;
import java.io.InputStream;
import java.io.PushbackInputStream;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
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
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Sort;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;
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
    /**
     * 标题关键词长度上限，与管理端搜索同口径。
     */
    private static final int LIBRARY_KEYWORD_MAX_LENGTH = 200;

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
    private static final long MAX_POSTER_UPLOAD_BYTES = 10L * 1024 * 1024;
    private DerivedAssetStorageService derivedAssetStorageService;

    @Autowired(required = false)
    void setDerivedAssetStorageService(DerivedAssetStorageService derivedAssetStorageService) {
        this.derivedAssetStorageService = derivedAssetStorageService;
    }

    /**
     * 将用户上传的本地图片保存为影视海报派生资产。
     *
     * @param ownerUserId 所属用户 ID
     * @param file 上传文件
     * @return 海报文件节点 ID
     */
    public VideoPosterUploadDto uploadPoster(UUID ownerUserId, MultipartFile file) {
        if (derivedAssetStorageService == null) {
            throw new BusinessException(ErrorCode.INTERNAL_ERROR, "海报存储服务未初始化");
        }
        if (file == null || file.isEmpty()) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "海报文件不能为空");
        }
        if (file.getSize() > MAX_POSTER_UPLOAD_BYTES) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "海报文件不能超过 10MB");
        }
        try (InputStream raw = file.getInputStream();
             PushbackInputStream input = new PushbackInputStream(raw, 32)) {
            byte[] header = input.readNBytes(32);
            input.unread(header);
            PosterImageType imageType = detectPosterImageType(header);
            UUID resourceId = UUID.randomUUID();
            UUID fileId = derivedAssetStorageService.store(
                    ownerUserId,
                    "VIDEO_POSTER",
                    resourceId,
                    AssetType.POSTER.getValue(),
                    "poster_" + resourceId + imageType.extension(),
                    imageType.mimeType(),
                    input
            );
            log.info("影视海报已上传: userId={}, fileId={}", ownerUserId, fileId);
            return new VideoPosterUploadDto(fileId);
        } catch (IOException ex) {
            throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "海报文件读取失败");
        }
    }

    private PosterImageType detectPosterImageType(byte[] bytes) {
        if (bytes.length >= 3
                && bytes[0] == (byte) 0xFF
                && bytes[1] == (byte) 0xD8
                && bytes[2] == (byte) 0xFF) {
            return new PosterImageType("image/jpeg", ".jpg");
        }
        if (matchesBytes(bytes, 0, new byte[]{(byte) 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A})) {
            return new PosterImageType("image/png", ".png");
        }
        if (matchesBytes(bytes, 0, "GIF87a".getBytes(StandardCharsets.US_ASCII))
                || matchesBytes(bytes, 0, "GIF89a".getBytes(StandardCharsets.US_ASCII))) {
            return new PosterImageType("image/gif", ".gif");
        }
        if (bytes.length >= 12
                && matchesBytes(bytes, 0, "RIFF".getBytes(StandardCharsets.US_ASCII))
                && matchesBytes(bytes, 8, "WEBP".getBytes(StandardCharsets.US_ASCII))) {
            return new PosterImageType("image/webp", ".webp");
        }
        throw new BusinessException(ErrorCode.PARAM_ERROR, "仅支持 JPEG、PNG、GIF 或 WebP 海报");
    }

    private boolean matchesBytes(byte[] bytes, int offset, byte[] expected) {
        if (bytes.length < offset + expected.length) {
            return false;
        }
        for (int index = 0; index < expected.length; index++) {
            if (bytes[offset + index] != expected[index]) {
                return false;
            }
        }
        return true;
    }

    private record PosterImageType(String mimeType, String extension) {
    }

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
        var scope = mediaLibraryAccessService.visibilityScope(ownerUserId);
        Set<UUID> readableLibraryIds = scope.librarySourceIds();
        MovieStatsDto stats = new MovieStatsDto(
                videoItemRepository.countReadableOriginalsByMediaType(
                        ownerUserId, scope.sharedSpaceReadable(), SpaceType.SHARED, readableLibraryIds, MediaType.MOVIE.getValue()),
                videoItemRepository.countReadableOriginalsByMediaType(
                        ownerUserId, scope.sharedSpaceReadable(), SpaceType.SHARED, readableLibraryIds, MediaType.EPISODE.getValue()),
                videoItemRepository.countReadableOriginalSeries(ownerUserId, scope.sharedSpaceReadable(), SpaceType.SHARED, readableLibraryIds),
                videoItemRepository.countReadableOriginalsByMetadataStatus(
                        ownerUserId, scope.sharedSpaceReadable(), SpaceType.SHARED, readableLibraryIds, MetadataStatus.FAILED.getValue()),
                videoFavoriteRepository.countByOwnerUserId(ownerUserId)
                        + seriesFavoriteRepository.countByOwnerUserId(ownerUserId),
                watchHistoryRepository.countByOwnerUserId(ownerUserId),
                videoCollectionRepository.countByOwnerUserIdAndCollectionTypeNot(
                        ownerUserId, CollectionType.WATCHLIST.getValue()),
                progressService.countIncomplete(ownerUserId, MediaPlaybackType.VIDEO)
        );
        PageRequest recentPage = PageRequest.of(
                0,
                48,
                Sort.by(Sort.Direction.DESC, "updatedAt").and(Sort.by(Sort.Direction.DESC, "id"))
        );
        List<MediaVideoItem> recentItems = deduplicateBySeries(
                videoItemRepository.findReadableOriginals(ownerUserId, scope.sharedSpaceReadable(), SpaceType.SHARED, readableLibraryIds, recentPage).getContent()
        ).stream().limit(12).toList();
        List<MovieVideoItemDto> recentlyAdded = videoItemDtoConverter.toVideoDtos(ownerUserId, recentItems);
        List<MediaPlaybackProgress> progresses = progressService.latest(ownerUserId, MediaPlaybackType.VIDEO);
        List<MovieContinueWatchingDto> continueWatching = toContinueWatchingDtos(ownerUserId, progresses);
        ZoneId zone = ZoneId.systemDefault();
        Instant todayStart = LocalDate.now(zone).atStartOfDay(zone).toInstant();
        long itemsAddedToday = videoItemRepository.countReadableOriginalsByMediaTypeCreatedSince(
                ownerUserId,
                scope.sharedSpaceReadable(),
                SpaceType.SHARED,
                readableLibraryIds,
                MediaType.MOVIE.getValue(),
                todayStart
        );
        return new MovieDashboardDto(stats, recentlyAdded, continueWatching, List.of(), itemsAddedToday);
    }

    /**
     * 旧版无分页影视列表。
     *
     * <p>保留该接口兼容既有客户端，但查询必须带服务端上限：全量加载在大型影库下
     * 会把全部条目与签名资源 URL 一次性拉进内存。新客户端应使用
     * {@link #libraryPage}。</p>
     */
    @Transactional(readOnly = true)
    public List<MovieVideoItemDto> movies(UUID ownerUserId) {
        var scope = mediaLibraryAccessService.visibilityScope(ownerUserId);
        Set<UUID> readableLibraryIds = scope.librarySourceIds();
        return videoItemDtoConverter.toVideoDtos(
                ownerUserId,
                videoItemRepository.findReadableOriginalsByMediaType(
                        ownerUserId, scope.sharedSpaceReadable(), SpaceType.SHARED,
                        readableLibraryIds,
                        MediaType.MOVIE.getValue(),
                        null,
                        legacyLibraryPage()
                ).getContent()
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
        return libraryPage(ownerUserId, mediaType, metadataStatus, page, size, sort, null);
    }

    /**
     * 分页获取视频库，支持标题关键词检索。
     *
     * <p>检索在数据侧完成，覆盖全库而不受客户端已加载分页限制；无关键词时走原分页查询。
     *
     * @param ownerUserId 当前用户 ID
     * @param mediaType 媒体类型
     * @param metadataStatus 可选元数据状态
     * @param page 页码
     * @param size 每页大小
     * @param sort 排序表达式
     * @param keyword 标题关键词，空白视为未填写
     * @return 有界的轻量影视条目页
     */
    @Transactional(readOnly = true)
    public PageResponse<MovieLibraryItemDto> libraryPage(
            UUID ownerUserId,
            String mediaType,
            String metadataStatus,
            int page,
            int size,
            String sort,
            String keyword
    ) {
        String normalizedMediaType = normalizeLibraryMediaType(mediaType);
        String normalizedStatus = normalizeLibraryMetadataStatus(metadataStatus);
        String titlePattern = buildLibraryTitlePattern(keyword);
        PageRequest pageable = createLibraryPageRequest(page, size, sort);
        var scope = mediaLibraryAccessService.visibilityScope(ownerUserId);
        Set<UUID> readableLibraryIds = scope.librarySourceIds();
        Page<MediaVideoItem> result = titlePattern == null
                ? videoItemRepository.findReadableOriginalsByMediaType(
                ownerUserId, scope.sharedSpaceReadable(), SpaceType.SHARED,
                readableLibraryIds,
                normalizedMediaType,
                normalizedStatus,
                pageable
        )
                : videoItemRepository.searchReadableOriginalsByMediaType(
                ownerUserId, scope.sharedSpaceReadable(), SpaceType.SHARED,
                readableLibraryIds,
                normalizedMediaType,
                normalizedStatus,
                titlePattern,
                pageable
        );
        return PageResponse.of(
                videoItemDtoConverter.toLibraryDtos(ownerUserId, result.getContent()),
                result.getNumber(),
                result.getSize(),
                result.getTotalElements()
        );
    }

    /**
     * 归一化标题检索串：小写、去首尾空白，并把 LIKE 通配符按字面量转义。
     *
     * <p>转义符是反斜杠，因此消费方必须写 {@code like :titlePattern escape '\'}：
     * PostgreSQL 的 {@code LIKE} 没有默认转义符，缺 {@code escape} 子句时反斜杠按普通字符匹配。
     *
     * <p>关键词长度设上限：前后都带通配的 {@code LIKE} 无法走索引，代价随行数与关键词长度相乘，
     * 上限口径与管理端搜索一致。
     *
     * @param keyword 原始关键词
     * @return 可用于 LIKE 的模式串；关键词空白时返回 null 表示不过滤
     * @throws BusinessException 关键词超过 {@value #LIBRARY_KEYWORD_MAX_LENGTH} 字符
     */
    private String buildLibraryTitlePattern(String keyword) {
        if (keyword == null || keyword.isBlank()) {
            return null;
        }
        String trimmed = keyword.trim();
        if (trimmed.length() > LIBRARY_KEYWORD_MAX_LENGTH) {
            throw new BusinessException(
                    ErrorCode.PARAM_ERROR,
                    "搜索关键词长度不能超过 " + LIBRARY_KEYWORD_MAX_LENGTH + " 个字符"
            );
        }
        String normalized = LikePatterns.escapeSpecials(
                trimmed.toLowerCase(Locale.ROOT));
        return "%" + normalized + "%";
    }

    @Transactional(readOnly = true)
    public List<MovieVideoItemDto> episodes(UUID ownerUserId) {
        var scope = mediaLibraryAccessService.visibilityScope(ownerUserId);
        Set<UUID> readableLibraryIds = scope.librarySourceIds();
        List<MediaVideoItem> items = deduplicateBySeries(
                videoItemRepository.findReadableOriginalsByMediaType(
                        ownerUserId, scope.sharedSpaceReadable(), SpaceType.SHARED,
                        readableLibraryIds,
                        MediaType.EPISODE.getValue(),
                        null,
                        legacyLibraryPage()
                ).getContent());
        return videoItemDtoConverter.toVideoDtos(ownerUserId, items);
    }

    /**
     * 旧版接口的固定上限查询：按更新时间倒序，最多返回 {@link PageClamps#MAX_SIZE} 条。
     */
    private PageRequest legacyLibraryPage() {
        return PageRequest.of(
                0,
                PageClamps.MAX_SIZE,
                Sort.by(Sort.Direction.DESC, "updatedAt").and(Sort.by(Sort.Direction.DESC, "id"))
        );
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
        var scope = mediaLibraryAccessService.visibilityScope(ownerUserId);
        Set<UUID> readableLibraryIds = scope.librarySourceIds();
        List<MediaTvSeries> items = tvSeriesRepository
                .findActiveReadableBySeriesType(ownerUserId, scope.sharedSpaceReadable(), SpaceType.SHARED, readableLibraryIds, seriesType);
        return toSeriesDtos(ownerUserId, items);
    }

    /**
     * 分页查询指定类型的可访问系列，按更新时间倒序，供系列网格滚动加载。
     *
     * @param ownerUserId 所有者用户 ID
     * @param seriesType 系列类型
     * @param page 页码，从零开始
     * @param size 每页条数
     * @return 系列分页
     */
    @Transactional(readOnly = true)
    public Page<MovieSeriesDto> seriesByTypePage(
            UUID ownerUserId, String seriesType, int page, int size, String keyword) {
        var scope = mediaLibraryAccessService.visibilityScope(ownerUserId);
        Set<UUID> readableLibraryIds = scope.librarySourceIds();
        Page<MediaTvSeries> items = tvSeriesRepository.findPageByActiveReadableAndSeriesType(
                ownerUserId, scope.sharedSpaceReadable(), SpaceType.SHARED,
                readableLibraryIds,
                seriesType,
                buildLibraryTitlePattern(keyword),
                PageRequest.of(PageClamps.safePage(page), PageClamps.safeSize(size)));
        return new PageImpl<>(
                toSeriesDtos(ownerUserId, items.getContent()),
                items.getPageable(),
                items.getTotalElements()
        );
    }

    /**
     * 查询当前用户收藏的系列（剧集与动漫），按收藏时间倒序。
     *
     * @param ownerUserId 所有者用户 ID
     * @return 收藏的系列列表
     */
    @Transactional(readOnly = true)
    public List<MovieSeriesDto> favoriteSeries(UUID ownerUserId) {
        return toFavoriteSeriesDtos(ownerUserId,
                seriesFavoriteRepository.findByOwnerUserIdOrderByCreatedAtDesc(ownerUserId));
    }

    /**
     * 分页查询用户收藏的系列，按收藏时间倒序，供收藏系列列表滚动加载。
     *
     * @param ownerUserId 所有者用户 ID
     * @param page 页码，从零开始
     * @param size 每页条数
     * @return 收藏系列分页
     */
    @Transactional(readOnly = true)
    public Page<MovieSeriesDto> favoriteSeriesPage(UUID ownerUserId, int page, int size) {
        Page<MediaSeriesFavorite> favorites = seriesFavoriteRepository.findPageByOwnerUserIdOrderByCreatedAtDesc(
                ownerUserId, PageRequest.of(PageClamps.safePage(page), PageClamps.safeSize(size)));
        return new PageImpl<>(
                toFavoriteSeriesDtos(ownerUserId, favorites.getContent()),
                favorites.getPageable(),
                favorites.getTotalElements()
        );
    }

    private List<MovieSeriesDto> toFavoriteSeriesDtos(UUID ownerUserId, List<MediaSeriesFavorite> favorites) {
        if (favorites.isEmpty()) {
            return List.of();
        }
        List<UUID> seriesIds = favorites.stream().map(MediaSeriesFavorite::getSeriesId).toList();
        var scope = mediaLibraryAccessService.visibilityScope(ownerUserId);
        Set<UUID> readableLibraryIds = scope.librarySourceIds();
        Map<UUID, MediaTvSeries> seriesIndex = tvSeriesRepository
                .findActiveReadableByIdIn(seriesIds, ownerUserId, scope.sharedSpaceReadable(), SpaceType.SHARED, readableLibraryIds)
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
        // 写操作按所有者取回，与 updateMetadata / deleteItem 同一口径：
        // requireReadableSeries 对 LOCAL 共享库只校验可读，任何能浏览该库的成员
        // 都能借此改掉别人创建的剧集标题与简介。库来源条目的跨所有者维护
        // 只放行持有 MEDIA_LIBRARY_MANAGE 的管理员，并仍经库来源校验。
        MediaTvSeries series = requireWritableSeries(ownerUserId, seriesId);
        boolean restoreOriginal = Boolean.TRUE.equals(request.restoreOriginal());
        if (restoreOriginal) {
            restoreSeriesOriginal(ownerUserId, series);
            series.setUpdatedAt(Instant.now());
            tvSeriesRepository.save(series);
        } else {
            String title = request.title() == null ? "" : request.title().trim();
            if (title.isEmpty()) {
                throw new BusinessException(ErrorCode.PARAM_ERROR, "剧集标题不能为空");
            }
            captureSeriesOriginal(ownerUserId, series);
            series.setTitle(title);
            if (request.overview() != null) {
                series.setOverview(request.overview());
            }
            if (request.seriesType() != null && !request.seriesType().isBlank()) {
                series.setSeriesType(request.seriesType().trim());
            }
            if (request.firstAirDate() != null) {
                series.setFirstAirDate(request.firstAirDate());
            }
            if (request.rating() != null) {
                if (!Double.isFinite(request.rating()) || request.rating() < 0 || request.rating() > 10) {
                    throw new BusinessException(ErrorCode.PARAM_ERROR, "评分须为 0 到 10 之间的数字");
                }
                series.setRating(request.rating());
            }
            if (request.genres() != null) {
                series.setGenres(request.genres().stream()
                        .filter(name -> name != null && !name.isBlank())
                        .map(name -> Map.<String, Object>of("name", name.trim()))
                        .toList());
            }
            if (request.cast() != null) {
                series.setCastMembers(request.cast().stream()
                        .filter(name -> name != null && !name.isBlank())
                        .map(name -> Map.<String, Object>of("name", name.trim()))
                        .toList());
            }
            // 样例 FilmEditor 的手填字段没有对应实体列，统一落 provider_metadata；
            // 客户端在 DTO 的 metadata 与 posterUrl 上读回同一份值。
            Map<String, Object> metadata = new LinkedHashMap<>(series.getMetadata() == null ? Map.of() : series.getMetadata());
            metadata.put("manualEdited", true);
            metadata.put("manualEditedAt", Instant.now().toString());
            if (request.runtime() != null) {
                String runtime = request.runtime().trim();
                if (runtime.isEmpty()) {
                    metadata.remove("manualRuntime");
                } else {
                    metadata.put("manualRuntime", runtime);
                }
            }
            if (Boolean.TRUE.equals(request.clearPoster())) {
                contentAssetService.clearPrimaryAsset(
                        ownerUserId,
                        series.getId(),
                        ResourceType.TV_SERIES.getValue(),
                        AssetType.POSTER.getValue());
                series.setPosterFileId(null);
                metadata.remove("manualPosterUrl");
            } else if (request.posterFileId() != null) {
                series.setPosterFileId(contentAssetService.setPrimaryFileAsset(
                        ownerUserId,
                        series.getId(),
                        ResourceType.TV_SERIES.getValue(),
                        AssetType.POSTER.getValue(),
                        request.posterFileId()));
                metadata.remove("manualPosterUrl");
            } else if (request.posterUrl() != null) {
                String posterUrl = MovieMetadataService.validatePosterUrl(request.posterUrl());
                if (posterUrl == null) {
                    metadata.remove("manualPosterUrl");
                } else {
                    series.setPosterFileId(contentAssetService.setPrimaryRemoteAsset(
                            ownerUserId,
                            series.getId(),
                            ResourceType.TV_SERIES.getValue(),
                            AssetType.POSTER.getValue(),
                            posterUrl));
                    metadata.put("manualPosterUrl", posterUrl);
                }
            }
            series.setMetadata(metadata);
            series.setUpdatedAt(Instant.now());
            tvSeriesRepository.save(series);
        }
        syncEventService.record(
                series.getOwnerUserId(),
                SyncScope.VIDEO,
                "VIDEO_SERIES",
                seriesId.toString(),
                SyncAction.UPDATED,
                series.getVersion(),
                Map.of("manualEdited", true)
        );
        return toSeriesDtos(ownerUserId, List.of(series)).getFirst();
    }

    /**
     * 解析可写的剧集：所有者本人，或可管理其媒体库来源的管理员。
     *
     * <p>媒体库条目的 {@code ownerUserId} 记录扫描执行者，并非唯一维护者；
     * 跨所有者写入只允许经 {@code MEDIA_LIBRARY_MANAGE} 与库来源校验，
     * 不得退回可读校验，否则会重新打开 53fccf59 修复的越权改写。</p>
     */
    private MediaTvSeries requireWritableSeries(UUID operatorUserId, UUID seriesId) {
        MediaTvSeries series = tvSeriesRepository.findById(seriesId)
                .orElseThrow(() -> new BusinessException(ErrorCode.MEDIA_NOT_FOUND, "媒体资源不存在"));
        if (series.getOwnerUserId().equals(operatorUserId)) {
            return series;
        }
        // 可读但不可写返回 403；连读权限都没有时仍按不存在处理，避免资源枚举。
        requireReadableSeriesOrNotFound(operatorUserId, series);
        if (series.getLibrarySourceId() != null) {
            try {
                mediaLibraryAccessService.requireManage(operatorUserId, series.getLibrarySourceId());
                return series;
            } catch (BusinessException exception) {
                throw new BusinessException(ErrorCode.FORBIDDEN, "无权修改该媒体资源元数据");
            }
        }
        throw new BusinessException(ErrorCode.FORBIDDEN, "无权修改该媒体资源元数据");
    }

    private void requireReadableSeriesOrNotFound(UUID viewerUserId, MediaTvSeries series) {
        var scope = mediaLibraryAccessService.visibilityScope(viewerUserId);
        boolean readable = tvSeriesRepository.findActiveReadableById(
                series.getId(),
                viewerUserId,
                scope.sharedSpaceReadable(),
                SpaceType.SHARED,
                scope.librarySourceIds()
        ).isPresent();
        if (!readable) {
            throw new BusinessException(ErrorCode.MEDIA_NOT_FOUND, "媒体资源不存在");
        }
    }

    @Transactional(readOnly = true)
    public List<MovieVideoItemDto> recent(UUID ownerUserId, int days) {
        int safeDays = days <= 0 ? 30 : Math.min(days, 365);
        Instant since = Instant.now().minus(safeDays, ChronoUnit.DAYS);
        var scope = mediaLibraryAccessService.visibilityScope(ownerUserId);
        Set<UUID> readableLibraryIds = scope.librarySourceIds();
        List<MediaVideoItem> items = deduplicateBySeries(videoItemRepository.findReadableOriginalsUpdatedAfter(
                ownerUserId, scope.sharedSpaceReadable(), SpaceType.SHARED,
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
        var scope = mediaLibraryAccessService.visibilityScope(ownerUserId);
        Set<UUID> readableLibraryIds = scope.librarySourceIds();
        List<MediaVideoItem> items = videoItemRepository.findReadableBySeriesId(
                ownerUserId, scope.sharedSpaceReadable(), SpaceType.SHARED,
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
        MediaVideoItem item = requireWritableVideo(ownerUserId, videoItemId);
        boolean restoreOriginal = Boolean.TRUE.equals(request.restoreOriginal());
        if (!restoreOriginal && (request.title() == null || request.title().isBlank())) {
            throw new BusinessException(
                    ErrorCode.PARAM_ERROR,
                    "标题不能为空"
            );
        }
        String newStatus = normalizeMetadataStatus(request.metadataStatus());
        boolean clearPoster = Boolean.TRUE.equals(request.clearPoster());
        if (item.getMovieId() == null && item.getEpisodeId() == null) {
            if (restoreOriginal) {
                throw new BusinessException(ErrorCode.PARAM_ERROR, "没有可恢复的原始影片元数据");
            }
            MediaMovie created = new MediaMovie();
            created.setId(UUID.randomUUID());
            created.setOwnerUserId(item.getOwnerUserId());
            created.setLibrarySourceId(item.getLibrarySourceId());
            created.setTitle(request.title().trim());
            created.setMetadataStatus(newStatus);
            created = movieRepository.save(created);
            item.setMovieId(created.getId());
        }
        if (item.getMovieId() != null) {
            MediaMovie movie = movieRepository.findById(item.getMovieId()).orElse(null);
            if (movie != null) {
                if (restoreOriginal) {
                    MovieMetadataService.RestoredPoster restored = MovieMetadataService.restoreOriginal(movie);
                    if (!restored.restored()) {
                        throw new BusinessException(ErrorCode.PARAM_ERROR, "没有可恢复的原始影片元数据");
                    }
                    if (restored.externalUrl() != null && !restored.externalUrl().isBlank()) {
                        movie.setPosterFileId(contentAssetService.setPrimaryRemoteAsset(
                                ownerUserId,
                                movie.getId(),
                                ResourceType.MOVIE.getValue(),
                                AssetType.POSTER.getValue(),
                                restored.fileNodeId(),
                                restored.externalUrl()));
                    } else if (restored.fileNodeId() != null) {
                        movie.setPosterFileId(contentAssetService.setPrimaryFileAsset(
                                ownerUserId,
                                movie.getId(),
                                ResourceType.MOVIE.getValue(),
                                AssetType.POSTER.getValue(),
                                restored.fileNodeId()));
                    } else {
                        contentAssetService.clearPrimaryAsset(
                                ownerUserId,
                                movie.getId(),
                                ResourceType.MOVIE.getValue(),
                                AssetType.POSTER.getValue());
                        movie.setPosterFileId(null);
                    }
                    newStatus = movie.getMetadataStatus();
                } else {
                    if (!MovieMetadataService.hasOriginal(movie)) {
                        String posterExternalUrl = contentAssetService.primaryExternalUrl(
                                ownerUserId,
                                movie.getId(),
                                ResourceType.MOVIE.getValue(),
                                AssetType.POSTER.getValue());
                        UUID posterFileNodeId = contentAssetService.primaryFileNodeId(
                                ownerUserId,
                                movie.getId(),
                                ResourceType.MOVIE.getValue(),
                                AssetType.POSTER.getValue());
                        MovieMetadataService.captureOriginal(movie, posterExternalUrl, posterFileNodeId);
                    }
                    movie.setTitle(request.title().trim());
                    movie.setOriginalTitle(blankToNull(request.originalTitle()));
                    movie.setReleaseDate(request.releaseDate());
                    movie.setOverview(blankToNull(request.overview()));
                    if (clearPoster) {
                        contentAssetService.clearPrimaryAsset(
                                ownerUserId,
                                movie.getId(),
                                ResourceType.MOVIE.getValue(),
                                AssetType.POSTER.getValue());
                        movie.setPosterFileId(null);
                    } else if (request.posterFileId() != null) {
                        movie.setPosterFileId(contentAssetService.setPrimaryFileAsset(
                                ownerUserId,
                                movie.getId(),
                                ResourceType.MOVIE.getValue(),
                                AssetType.POSTER.getValue(),
                                request.posterFileId()));
                    } else if (request.posterUrl() != null) {
                        String posterUrl = MovieMetadataService.validatePosterUrl(request.posterUrl());
                        if (posterUrl != null) {
                            movie.setPosterFileId(contentAssetService.setPrimaryRemoteAsset(
                                    ownerUserId,
                                    movie.getId(),
                                    ResourceType.MOVIE.getValue(),
                                    AssetType.POSTER.getValue(),
                                    posterUrl));
                        } else {
                            contentAssetService.clearPrimaryAsset(
                                    ownerUserId,
                                    movie.getId(),
                                    ResourceType.MOVIE.getValue(),
                                    AssetType.POSTER.getValue());
                            movie.setPosterFileId(null);
                        }
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
                    } else if (Boolean.TRUE.equals(request.clearRuntime())) {
                        movie.setRuntimeSeconds(null);
                    }
                    movie.setMetadataStatus(newStatus);
                    MovieMetadataService.applySupplemental(movie, request);
                    if (clearPoster || request.posterFileId() != null) {
                        Map<String, Object> metadata = new LinkedHashMap<>(
                                movie.getMetadata() == null ? Map.of() : movie.getMetadata());
                        metadata.remove("manualPosterUrl");
                        movie.setMetadata(metadata);
                    }
                }
                movieRepository.save(movie);
            }
        } else if (item.getEpisodeId() != null) {
            if (restoreOriginal) {
                throw new BusinessException(ErrorCode.PARAM_ERROR, "剧集元数据没有原始快照");
            }
            MediaTvEpisode episode = episodeRepository.findById(item.getEpisodeId()).orElse(null);
            if (episode != null) {
                episode.setTitle(request.title().trim());
                episode.setOriginalTitle(blankToNull(request.originalTitle()));
                episode.setOverview(blankToNull(request.overview()));
                if (request.releaseDate() != null) {
                    episode.setAirDate(request.releaseDate());
                }
                if (request.rating() != null) {
                    if (!Double.isFinite(request.rating()) || request.rating() < 0 || request.rating() > 10) {
                        throw new BusinessException(ErrorCode.PARAM_ERROR, "评分须为 0 到 10 之间的数字");
                    }
                    episode.setRating(request.rating());
                }
                if (request.runtimeSeconds() != null && request.runtimeSeconds() > 0) {
                    episode.setRuntimeSeconds(request.runtimeSeconds());
                } else if (Boolean.TRUE.equals(request.clearRuntime())) {
                    episode.setRuntimeSeconds(null);
                }
                episode.setMetadataStatus(newStatus);
                Map<String, Object> metadata = episode.getMetadata() == null
                        ? new LinkedHashMap<>()
                        : new LinkedHashMap<>(episode.getMetadata());
                metadata.put("manualEdited", true);
                metadata.put("manualEditedAt", Instant.now().toString());
                if (request.genres() != null) {
                    metadata.put("manualGenres", request.genres().stream()
                            .filter(Objects::nonNull)
                            .map(String::trim)
                            .filter(value -> !value.isEmpty())
                            .distinct()
                            .toList());
                }
                if (request.cast() != null) {
                    metadata.put("manualCast", request.cast().stream()
                            .filter(Objects::nonNull)
                            .map(String::trim)
                            .filter(value -> !value.isEmpty())
                            .distinct()
                            .toList());
                }
                if (clearPoster) {
                    contentAssetService.clearPrimaryAsset(
                            ownerUserId,
                            item.getId(),
                            ResourceType.VIDEO_ITEM.getValue(),
                            AssetType.POSTER.getValue());
                    episode.setStillFileId(null);
                    metadata.remove("manualPosterUrl");
                } else if (request.posterFileId() != null) {
                    UUID posterFileId = contentAssetService.setPrimaryFileAsset(
                            ownerUserId,
                            item.getId(),
                            ResourceType.VIDEO_ITEM.getValue(),
                            AssetType.POSTER.getValue(),
                            request.posterFileId());
                    episode.setStillFileId(posterFileId);
                    metadata.remove("manualPosterUrl");
                } else if (request.posterUrl() != null) {
                    String posterUrl = MovieMetadataService.validatePosterUrl(request.posterUrl());
                    if (posterUrl != null) {
                        UUID posterFileId = contentAssetService.setPrimaryRemoteAsset(
                                ownerUserId,
                                item.getId(),
                                ResourceType.VIDEO_ITEM.getValue(),
                                AssetType.POSTER.getValue(),
                                posterUrl);
                        episode.setStillFileId(posterFileId);
                        metadata.put("manualPosterUrl", posterUrl);
                    } else {
                        contentAssetService.clearPrimaryAsset(
                                ownerUserId,
                                item.getId(),
                                ResourceType.VIDEO_ITEM.getValue(),
                                AssetType.POSTER.getValue());
                        episode.setStillFileId(null);
                        metadata.remove("manualPosterUrl");
                    }
                }
                episode.setMetadata(metadata);
                episodeRepository.save(episode);
            }
        }
        // 同步 metadataStatus 到 VideoItem 本身
        item.setMetadataStatus(newStatus);
        videoItemRepository.save(item);
        recordVideoEvent(item.getOwnerUserId(), item, SyncAction.UPDATED);
        invalidateDashboardCache(item.getOwnerUserId());
        if (!item.getOwnerUserId().equals(ownerUserId)) {
            invalidateDashboardCache(ownerUserId);
        }
        return videoItemDtoConverter.toVideoDto(ownerUserId, item);
    }

    /**
     * 解析可写的视频条目：所有者本人，或可管理其媒体库来源的管理员。
     *
     * <p>同 {@link #requireWritableSeries}：媒体库条目的 owner 是扫描执行者，
     * 跨所有者维护只能经 MEDIA_LIBRARY_MANAGE，不得放宽为可读权限。</p>
     */
    private MediaVideoItem requireWritableVideo(UUID operatorUserId, UUID videoItemId) {
        MediaVideoItem item = videoItemRepository.findById(videoItemId)
                .orElseThrow(() -> new BusinessException(ErrorCode.MEDIA_NOT_FOUND, "媒体资源不存在"));
        if (item.getOwnerUserId().equals(operatorUserId)) {
            return item;
        }
        // 可读但不可写返回 403；读不到的条目仍按不存在处理，避免资源枚举。
        if (mediaContentAccessService.findReadableVideo(operatorUserId, videoItemId).isEmpty()) {
            throw new BusinessException(ErrorCode.MEDIA_NOT_FOUND, "媒体资源不存在");
        }
        if (item.getLibrarySourceId() != null) {
            try {
                mediaLibraryAccessService.requireManage(operatorUserId, item.getLibrarySourceId());
                return item;
            } catch (BusinessException exception) {
                throw new BusinessException(ErrorCode.FORBIDDEN, "无权修改该媒体资源元数据");
            }
        }
        throw new BusinessException(ErrorCode.FORBIDDEN, "无权修改该媒体资源元数据");
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
        var scope = mediaLibraryAccessService.visibilityScope(ownerUserId);
        Set<UUID> readableLibraryIds = scope.librarySourceIds();
        List<MediaVideoItem> items = videoItemRepository.findReadableByIds(
                ownerUserId, scope.sharedSpaceReadable(), SpaceType.SHARED,
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

        List<MovieContinueWatchingDto> mapped = progressItemIds.entrySet().stream()
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
                                    progress.getUpdatedAt(),
                                    item.mediaType(),
                                    item.seriesId(),
                                    item.seasonNumber(),
                                    item.episodeNumber()
                            );
                        })
                        .stream())
                .toList();
        return dedupeContinueWatchingBySeries(mapped);
    }

    /**
     * 同一剧集只保留最近一次未看完进度，避免继续观看出现多张同系列分集卡。
     * 电影（seriesId 为空）不合并；组内按 updatedAt 取最新。
     */
    private List<MovieContinueWatchingDto> dedupeContinueWatchingBySeries(
            List<MovieContinueWatchingDto> entries
    ) {
        Map<UUID, MovieContinueWatchingDto> latestBySeries = new LinkedHashMap<>();
        List<MovieContinueWatchingDto> movies = new ArrayList<>();
        for (MovieContinueWatchingDto entry : entries) {
            if (entry.seriesId() == null) {
                movies.add(entry);
                continue;
            }
            MovieContinueWatchingDto current = latestBySeries.get(entry.seriesId());
            Instant currentAt = current == null || current.updatedAt() == null
                    ? Instant.EPOCH
                    : current.updatedAt();
            Instant entryAt = entry.updatedAt() == null ? Instant.EPOCH : entry.updatedAt();
            if (current == null || entryAt.isAfter(currentAt)) {
                latestBySeries.put(entry.seriesId(), entry);
            }
        }
        List<MovieContinueWatchingDto> result = new ArrayList<>(movies);
        result.addAll(latestBySeries.values());
        result.sort((left, right) -> {
            Instant leftAt = left.updatedAt() == null ? Instant.EPOCH : left.updatedAt();
            Instant rightAt = right.updatedAt() == null ? Instant.EPOCH : right.updatedAt();
            return rightAt.compareTo(leftAt);
        });
        return result;
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
        if (resolvedPosterUrl == null) {
            Object manual = item.getMetadata().get("manualPosterUrl");
            if (manual instanceof String url && !url.isBlank()) {
                resolvedPosterUrl = url;
            }
        }
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
        var scope = mediaLibraryAccessService.visibilityScope(ownerUserId);
        Set<UUID> readableLibraryIds = scope.librarySourceIds();
        MediaTvSeries series = tvSeriesRepository.findActiveReadableById(
                        seriesId,
                        ownerUserId, scope.sharedSpaceReadable(), SpaceType.SHARED,
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
        boolean writable = series.getOwnerUserId().equals(ownerUserId)
                || (series.getLibrarySourceId() != null
                    && mediaLibraryAccessService.canManageLibraries(ownerUserId));
        return new MovieSeriesDetailDto(
                seriesDto, seasonDtos, seriesDto.castMembers(), seriesDto.crewMembers(), writable);
    }

    @Transactional(readOnly = true)
    public MovieSeasonDetailDto seasonDetail(UUID ownerUserId, UUID seriesId, int seasonNumber) {
        var scope = mediaLibraryAccessService.visibilityScope(ownerUserId);
        Set<UUID> readableLibraryIds = scope.librarySourceIds();
        MediaTvSeries series = tvSeriesRepository.findActiveReadableById(
                        seriesId,
                        ownerUserId, scope.sharedSpaceReadable(), SpaceType.SHARED,
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
                        ownerUserId, scope.sharedSpaceReadable(), SpaceType.SHARED,
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
    private void captureSeriesOriginal(UUID ownerUserId, MediaTvSeries series) {
        Map<String, Object> metadata = new LinkedHashMap<>(
                series.getMetadata() == null ? Map.of() : series.getMetadata());
        if (metadata.containsKey("manualMetadataOriginal")) {
            return;
        }
        Map<String, Object> original = new LinkedHashMap<>();
        original.put("title", series.getTitle());
        original.put("overview", series.getOverview());
        original.put("seriesType", series.getSeriesType());
        original.put("firstAirDate", series.getFirstAirDate() == null ? null : series.getFirstAirDate().toString());
        original.put("rating", series.getRating());
        original.put("genres", series.getGenres() == null ? List.of() : new ArrayList<>(series.getGenres()));
        original.put("castMembers", series.getCastMembers() == null ? List.of() : new ArrayList<>(series.getCastMembers()));
        UUID posterFileNodeId = contentAssetService.primaryFileNodeId(
                ownerUserId,
                series.getId(),
                ResourceType.TV_SERIES.getValue(),
                AssetType.POSTER.getValue());
        UUID effectivePosterId = posterFileNodeId != null ? posterFileNodeId : series.getPosterFileId();
        original.put("posterFileId", effectivePosterId == null ? null : effectivePosterId.toString());
        original.put("posterExternalUrl", contentAssetService.primaryExternalUrl(
                ownerUserId,
                series.getId(),
                ResourceType.TV_SERIES.getValue(),
                AssetType.POSTER.getValue()));
        original.put("metadata", new LinkedHashMap<>(metadata));
        metadata.put("manualMetadataOriginal", original);
        series.setMetadata(metadata);
    }

    @SuppressWarnings("unchecked")
    private void restoreSeriesOriginal(UUID ownerUserId, MediaTvSeries series) {
        Map<String, Object> metadata = series.getMetadata() == null ? Map.of() : series.getMetadata();
        Object rawOriginal = metadata.get("manualMetadataOriginal");
        if (!(rawOriginal instanceof Map<?, ?> originalMap) || originalMap.isEmpty()) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "没有可恢复的原始剧集元数据");
        }
        Object title = originalMap.get("title");
        if (title != null) {
            series.setTitle(title.toString());
        }
        series.setOverview(originalMap.get("overview") == null ? null : originalMap.get("overview").toString());
        if (originalMap.get("seriesType") != null) {
            series.setSeriesType(originalMap.get("seriesType").toString());
        }
        Object firstAirDate = originalMap.get("firstAirDate");
        series.setFirstAirDate(firstAirDate == null || firstAirDate.toString().isBlank()
                ? null
                : LocalDate.parse(firstAirDate.toString()));
        Object rating = originalMap.get("rating");
        series.setRating(rating instanceof Number number ? number.doubleValue() : null);
        if (originalMap.get("genres") instanceof List<?> genresList) {
            series.setGenres((List<Map<String, Object>>) (List<?>) new ArrayList<>(genresList));
        }
        if (originalMap.get("castMembers") instanceof List<?> castList) {
            series.setCastMembers((List<Map<String, Object>>) (List<?>) new ArrayList<>(castList));
        }
        String posterExternalUrl = originalMap.get("posterExternalUrl") == null
                ? null
                : originalMap.get("posterExternalUrl").toString();
        String posterFileIdText = originalMap.get("posterFileId") == null
                ? null
                : originalMap.get("posterFileId").toString();
        UUID posterFileId = posterFileIdText == null || posterFileIdText.isBlank()
                ? null
                : UUID.fromString(posterFileIdText);
        if (posterExternalUrl != null && !posterExternalUrl.isBlank()) {
            series.setPosterFileId(contentAssetService.setPrimaryRemoteAsset(
                    ownerUserId,
                    series.getId(),
                    ResourceType.TV_SERIES.getValue(),
                    AssetType.POSTER.getValue(),
                    posterFileId,
                    posterExternalUrl));
        } else if (posterFileId != null) {
            series.setPosterFileId(contentAssetService.setPrimaryFileAsset(
                    ownerUserId,
                    series.getId(),
                    ResourceType.TV_SERIES.getValue(),
                    AssetType.POSTER.getValue(),
                    posterFileId));
        } else {
            contentAssetService.clearPrimaryAsset(
                    ownerUserId,
                    series.getId(),
                    ResourceType.TV_SERIES.getValue(),
                    AssetType.POSTER.getValue());
            series.setPosterFileId(null);
        }
        Map<String, Object> restoredMetadata = new LinkedHashMap<>();
        if (originalMap.get("metadata") instanceof Map<?, ?> inner) {
            inner.forEach((k, v) -> {
                if (k instanceof String key) {
                    restoredMetadata.put(key, v);
                }
            });
        }
        series.setMetadata(restoredMetadata);
    }

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
