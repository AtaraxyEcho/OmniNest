package com.omninest.modules.video.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.argThat;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.modules.media.domain.AssetType;
import com.omninest.modules.media.domain.ResourceType;
import com.omninest.common.cache.ReadThroughCache;
import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncScope;
import com.omninest.modules.file.service.FileDeletionService;
import com.omninest.modules.file.service.FileContentAvailabilityQueryService;
import com.omninest.modules.file.service.FilePurgeOrigin;
import com.omninest.modules.file.service.FileQueryService;
import com.omninest.modules.media.domain.MediaPlaybackProgress;
import com.omninest.modules.media.domain.MediaPlaybackType;
import com.omninest.modules.media.service.MediaPlaybackProgressService;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.video.repository.ContentAssetRepository;
import com.omninest.modules.video.domain.MediaMovie;
import com.omninest.modules.video.domain.MediaSeriesFavorite;
import com.omninest.modules.video.domain.MediaTvSeries;
import com.omninest.modules.video.domain.MediaVideoItem;
import com.omninest.modules.video.dto.MovieDtos.MovieMetadataUpdateRequest;
import com.omninest.modules.video.dto.MovieDtos.UpdateSeriesMetadataRequest;
import com.omninest.modules.video.repository.MediaMovieRepository;
import com.omninest.modules.video.repository.MediaSeriesFavoriteRepository;
import com.omninest.modules.video.repository.MediaTvEpisodeRepository;
import com.omninest.modules.video.repository.MediaTvSeasonRepository;
import com.omninest.modules.video.repository.MediaTvSeriesRepository;
import com.omninest.modules.video.repository.MediaVideoItemRepository;
import com.omninest.modules.video.repository.MediaVideoCollectionRepository;
import com.omninest.modules.video.repository.MediaVideoFavoriteRepository;
import com.omninest.modules.video.repository.MediaWatchHistoryRepository;
import java.time.Instant;
import java.time.LocalDate;
import java.util.function.Supplier;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;

/**
 * 影视库聚合与元数据更新测试。
 *
 * @author OmniNest
 */
class MovieLibraryServiceTest {
    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID MOVIE_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");
    private static final UUID LOGICAL_MOVIE_ID = UUID.fromString("50000000-0000-0000-0000-000000000001");
    private static final UUID FILE_NODE_ID = UUID.fromString("30000000-0000-0000-0000-000000000001");
    private static final UUID SERIES_ID = UUID.fromString("60000000-0000-0000-0000-000000000001");

    private final MediaVideoItemRepository videoItemRepository = mock(MediaVideoItemRepository.class);
    private final MediaTvSeriesRepository tvSeriesRepository = mock(MediaTvSeriesRepository.class);
    private final MediaTvSeasonRepository tvSeasonRepository = mock(MediaTvSeasonRepository.class);
    private final MediaPlaybackProgressService progressService =
            mock(MediaPlaybackProgressService.class);
    private final FileDeletionService fileDeletionService = mock(FileDeletionService.class);
    private final FileQueryService fileQueryService = mock(FileQueryService.class);
    private final ContentAssetService contentAssetService = mock(ContentAssetService.class);
    private final MediaMovieRepository movieRepository = mock(MediaMovieRepository.class);
    private final MediaTvEpisodeRepository episodeRepository = mock(MediaTvEpisodeRepository.class);
    private final ContentAssetRepository contentAssetRepository = mock(ContentAssetRepository.class);
    private final FileContentAvailabilityQueryService fileContentAvailabilityQueryService =
            mock(FileContentAvailabilityQueryService.class);
    private final MediaPlaybackTokenService mediaPlaybackTokenService = mock(MediaPlaybackTokenService.class);
    private final MediaSyncEventService syncEventService = mock(MediaSyncEventService.class);
    private final MediaLibraryAccessService mediaLibraryAccessService = mock(MediaLibraryAccessService.class);
    private final MediaContentAccessService mediaContentAccessService = mock(MediaContentAccessService.class);
    private final MediaSeriesFavoriteRepository seriesFavoriteRepository = mock(MediaSeriesFavoriteRepository.class);
    private final MediaVideoFavoriteRepository videoFavoriteRepository = mock(MediaVideoFavoriteRepository.class);
    private final MediaWatchHistoryRepository watchHistoryRepository = mock(MediaWatchHistoryRepository.class);
    private final MediaVideoCollectionRepository videoCollectionRepository = mock(MediaVideoCollectionRepository.class);
    private final ReadThroughCache readThroughCache = mock(ReadThroughCache.class, invocation -> {
        if ("getOrLoad".equals(invocation.getMethod().getName())) {
            Supplier<?> loader = invocation.getArgument(2);
            return loader.get();
        }
        return null;
    });
    // 使用真实 converter 配合 mock 的底层依赖，避免 spy 在具体类上的兼容问题
    private final VideoCatalogMappers catalogMappers =
            new VideoCatalogMappers(fileQueryService);
    private final VideoItemDtoConverter videoItemDtoConverter =
            new VideoItemDtoConverter(
                    movieRepository,
                    episodeRepository,
                    tvSeriesRepository,
                    fileQueryService,
                    new VideoCatalogMappers(fileQueryService),
                    fileContentAvailabilityQueryService,
                    contentAssetRepository,
                    mediaPlaybackTokenService
            );
    private final MovieLibraryService movieLibraryService =
            new MovieLibraryService(
                    videoItemRepository,
                    tvSeriesRepository,
                    tvSeasonRepository,
                    progressService,
                    fileDeletionService,
                    fileQueryService,
                    catalogMappers,
                    contentAssetService,
                    movieRepository,
                    episodeRepository,
                    videoItemDtoConverter,
                    readThroughCache,
                    syncEventService,
                    mediaLibraryAccessService,
                    mediaContentAccessService,
                    seriesFavoriteRepository,
                    mediaPlaybackTokenService,
                    videoFavoriteRepository,
                    watchHistoryRepository,
                    videoCollectionRepository
            );

    @Test
    void dashboardAggregatesLibraryStatsAndContinueWatching() {
        MediaVideoItem movie = movie("Inception", "MOVIE");
        MediaMovie logicalMovie = logicalMovie("Inception");
        logicalMovie.setPosterFileId(UUID.fromString("70000000-0000-0000-0000-000000000001"));
        MediaPlaybackProgress progress = new MediaPlaybackProgress();
        progress.setMediaType(MediaPlaybackType.VIDEO.value());
        progress.setMediaKey(MOVIE_ID.toString());
        progress.setOwnerUserId(OWNER_ID);
        progress.setPositionSeconds(1200);
        progress.setDurationSeconds(7200);
        progress.setUpdatedAt(Instant.parse("2026-05-21T10:00:00Z"));

        when(mediaLibraryAccessService.findReadableLibraryIds(OWNER_ID)).thenReturn(Set.of());
        when(videoItemRepository.countReadableOriginalsByMediaType(OWNER_ID, Set.of(), "MOVIE"))
                .thenReturn(1L);
        when(videoItemRepository.countReadableOriginalsByMediaType(OWNER_ID, Set.of(), "EPISODE"))
                .thenReturn(0L);
        when(videoItemRepository.countReadableOriginalSeries(OWNER_ID, Set.of())).thenReturn(0L);
        when(videoItemRepository.countReadableOriginalsByMetadataStatus(OWNER_ID, Set.of(), "FAILED"))
                .thenReturn(0L);
        when(videoFavoriteRepository.countByOwnerUserId(OWNER_ID)).thenReturn(2L);
        when(watchHistoryRepository.countByOwnerUserId(OWNER_ID)).thenReturn(3L);
        when(videoCollectionRepository.countByOwnerUserId(OWNER_ID)).thenReturn(1L);
        when(seriesFavoriteRepository.countByOwnerUserId(OWNER_ID)).thenReturn(1L);
        when(progressService.countIncomplete(OWNER_ID, MediaPlaybackType.VIDEO)).thenReturn(1L);
        when(videoItemRepository.findReadableOriginals(eq(OWNER_ID), eq(Set.of()), any(Pageable.class)))
                .thenReturn(new PageImpl<>(List.of(movie)));
        when(progressService.latest(OWNER_ID, MediaPlaybackType.VIDEO)).thenReturn(List.of(progress));
        // converter 需要通过 movieRepository.findAllById 加载 movie
        when(movieRepository.findAllById(any())).thenReturn(List.of(logicalMovie));
        when(videoItemRepository.findReadableByIds(OWNER_ID, Set.of(), List.of(MOVIE_ID)))
                .thenReturn(List.of(movie));

        var dashboard = movieLibraryService.dashboard(OWNER_ID);

        assertThat(dashboard.stats().movieCount()).isEqualTo(1);
        assertThat(dashboard.stats().episodeCount()).isZero();
        assertThat(dashboard.stats().seriesCount()).isZero();
        assertThat(dashboard.stats().scrapeFailedCount()).isZero();
        assertThat(dashboard.stats().favoritesCount()).isEqualTo(3);
        assertThat(dashboard.stats().historyCount()).isEqualTo(3);
        assertThat(dashboard.stats().collectionsCount()).isEqualTo(1);
        assertThat(dashboard.stats().continueWatchingCount()).isEqualTo(1);
        assertThat(dashboard.recentlyAdded()).isNotEmpty();
        assertThat(dashboard.recentlyAdded()).first().extracting("title").isEqualTo("Inception");
        assertThat(dashboard.continueWatching()).singleElement().extracting("progressPercent").isEqualTo(16.67);
    }

    @Test
    void libraryPageBoundsPageSizeAndReturnsLightweightItems() {
        MediaVideoItem movie = movie("Inception", "MOVIE");
        MediaMovie logicalMovie = logicalMovie("Inception");
        logicalMovie.setReleaseDate(LocalDate.of(2010, 7, 16));
        logicalMovie.setRating(8.8);
        when(mediaLibraryAccessService.findReadableLibraryIds(OWNER_ID)).thenReturn(Set.of());
        when(videoItemRepository.findReadableOriginalsByMediaType(
                eq(OWNER_ID),
                eq(Set.of()),
                eq("MOVIE"),
                isNull(),
                argThat(pageable -> pageable.getPageNumber() == 0
                        && pageable.getPageSize() == 12
                        && pageable.getSort().getOrderFor("updatedAt").isAscending())
        )).thenReturn(new PageImpl<>(List.of(movie), PageRequest.of(0, 12), 1));
        when(movieRepository.findAllById(any())).thenReturn(List.of(logicalMovie));

        var result = movieLibraryService.libraryPage(
                OWNER_ID,
                "MOVIE",
                "ALL",
                -1,
                1,
                "unsupported,asc"
        );

        assertThat(result.page()).isZero();
        assertThat(result.size()).isEqualTo(12);
        assertThat(result.totalElements()).isEqualTo(1);
        assertThat(result.items()).singleElement().satisfies(item -> {
            assertThat(item.title()).isEqualTo("Inception");
            assertThat(item.releaseDate()).isEqualTo(LocalDate.of(2010, 7, 16));
            assertThat(item.rating()).isEqualTo(8.8);
            assertThat(item.availabilityStatus()).isEqualTo("AVAILABLE");
        });
    }

    @Test
    void updateMetadataStoresManualInfoAndCoverAssets() {
        MediaVideoItem movie = movie("旧标题", "MOVIE");
        MediaMovie logicalMovie = logicalMovie("旧标题");
        UUID posterFileId = UUID.fromString("40000000-0000-0000-0000-000000000001");
        UUID backdropFileId = UUID.fromString("50000000-0000-0000-0000-000000000001");
        when(videoItemRepository.findByIdAndOwnerUserId(MOVIE_ID, OWNER_ID)).thenReturn(Optional.of(movie));
        when(movieRepository.findById(LOGICAL_MOVIE_ID)).thenReturn(Optional.of(logicalMovie));
        when(movieRepository.save(any(MediaMovie.class))).thenAnswer(inv -> inv.getArgument(0));
        when(contentAssetService.setPrimaryFileAsset(any(), any(), any(), any(), any()))
                .thenAnswer(inv -> inv.getArgument(4));
        // converter 需要通过 movieRepository.findAllById 加载 movie
        when(movieRepository.findAllById(any())).thenReturn(List.of(logicalMovie));

        var result = movieLibraryService.updateMetadata(
                OWNER_ID,
                MOVIE_ID,
                new MovieMetadataUpdateRequest(
                        "飞驰人生",
                        "Pegasus",
                        LocalDate.of(2024, 2, 10),
                        "热血赛车故事",
                        posterFileId,
                        backdropFileId,
                        7200,
                        "MANUAL"
                )
        );

        verify(movieRepository).save(any(MediaMovie.class));
        verify(contentAssetService).setPrimaryFileAsset(
                OWNER_ID,
                LOGICAL_MOVIE_ID,
                ResourceType.MOVIE.getValue(),
                AssetType.POSTER.getValue(),
                posterFileId
        );
        verify(contentAssetService).setPrimaryFileAsset(
                OWNER_ID,
                LOGICAL_MOVIE_ID,
                ResourceType.MOVIE.getValue(),
                AssetType.BACKDROP.getValue(),
                backdropFileId
        );
        assertThat(logicalMovie.getTitle()).isEqualTo("飞驰人生");
        assertThat(logicalMovie.getOriginalTitle()).isEqualTo("Pegasus");
        assertThat(logicalMovie.getPosterFileId()).isEqualTo(posterFileId);
        assertThat(logicalMovie.getBackdropFileId()).isEqualTo(backdropFileId);
        assertThat(logicalMovie.getMetadataStatus()).isEqualTo("MANUAL");
        assertThat(logicalMovie.getMetadata()).containsEntry("manualEdited", true);
    }

    @Test
    void deleteItemPermanentlyDeletesLinkedFile() {
        MediaVideoItem movie = movie("Inception", "MOVIE");
        when(videoItemRepository.findByIdAndOwnerUserId(MOVIE_ID, OWNER_ID)).thenReturn(Optional.of(movie));

        movieLibraryService.deleteItem(OWNER_ID, MOVIE_ID);

        verify(fileDeletionService).deletePermanently(
                eq(OWNER_ID),
                eq(movie.getFileNodeId()),
                eq(false),
                any(FilePurgeOrigin.class),
                isNull()
        );
    }

    @Test
    void favoriteSeriesReturnsReadableSeriesInFavoriteOrder() {
        MediaSeriesFavorite newest = new MediaSeriesFavorite();
        newest.setOwnerUserId(OWNER_ID);
        newest.setSeriesId(SERIES_ID);
        MediaSeriesFavorite oldest = new MediaSeriesFavorite();
        oldest.setOwnerUserId(OWNER_ID);
        oldest.setSeriesId(MOVIE_ID);
        when(seriesFavoriteRepository.findByOwnerUserIdOrderByCreatedAtDesc(OWNER_ID))
                .thenReturn(List.of(newest, oldest));
        when(mediaLibraryAccessService.findReadableLibraryIds(OWNER_ID)).thenReturn(Set.of());
        MediaTvSeries series = new MediaTvSeries();
        series.setId(SERIES_ID);
        series.setOwnerUserId(OWNER_ID);
        series.setTitle("Diablo");
        when(tvSeriesRepository.findActiveReadableByIdIn(any(), eq(OWNER_ID), eq(Set.of())))
                .thenReturn(List.of(series));
        when(contentAssetService.primarySeriesAssets(OWNER_ID, List.of(SERIES_ID)))
                .thenReturn(Map.of());
        when(seriesFavoriteRepository.findByOwnerUserIdAndSeriesIdIn(eq(OWNER_ID), any()))
                .thenReturn(List.of());

        var result = movieLibraryService.favoriteSeries(OWNER_ID);

        assertThat(result).singleElement().extracting("id").isEqualTo(SERIES_ID);
    }

    @Test
    void updateSeriesMetadataTrimsTitleAndRecordsSyncEvent() {
        MediaTvSeries series = new MediaTvSeries();
        series.setId(SERIES_ID);
        series.setOwnerUserId(OWNER_ID);
        series.setTitle("Old Title");
        when(mediaContentAccessService.requireReadableSeries(OWNER_ID, SERIES_ID)).thenReturn(series);
        when(tvSeriesRepository.save(any())).thenAnswer(invocation -> invocation.getArgument(0));
        when(contentAssetService.primarySeriesAssets(OWNER_ID, List.of(SERIES_ID)))
                .thenReturn(Map.of());
        when(seriesFavoriteRepository.findByOwnerUserIdAndSeriesIdIn(eq(OWNER_ID), any()))
                .thenReturn(List.of());

        var updated = movieLibraryService.updateSeriesMetadata(
                OWNER_ID,
                SERIES_ID,
                new UpdateSeriesMetadataRequest("  新标题 ", "新简介")
        );

        assertThat(updated.title()).isEqualTo("新标题");
        assertThat(series.getOverview()).isEqualTo("新简介");
        verify(tvSeriesRepository).save(series);
        verify(syncEventService).record(
                eq(OWNER_ID),
                eq(SyncScope.VIDEO),
                eq("VIDEO_SERIES"),
                eq(SERIES_ID.toString()),
                eq(SyncAction.UPDATED),
                any(),
                any()
        );
    }

    private MediaVideoItem movie(String title, String mediaType) {
        MediaVideoItem item = new MediaVideoItem();
        item.setId(MOVIE_ID);
        item.setOwnerUserId(OWNER_ID);
        item.setFileNodeId(FILE_NODE_ID);
        item.setMediaType(mediaType);
        item.setMovieId(LOGICAL_MOVIE_ID);
        item.setMetadataStatus("MATCHED");
        item.setUpdatedAt(Instant.parse("2026-05-21T09:00:00Z"));
        return item;
    }

    private MediaMovie logicalMovie(String title) {
        MediaMovie m = new MediaMovie();
        m.setId(LOGICAL_MOVIE_ID);
        m.setOwnerUserId(OWNER_ID);
        m.setTitle(title);
        m.setMetadataStatus("MATCHED");
        return m;
    }
}
