package com.omninest.modules.video.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.argThat;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.atLeast;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.cache.ReadThroughCache;
import com.omninest.modules.video.domain.MediaMovie;
import com.omninest.modules.video.domain.MediaTvEpisode;
import com.omninest.modules.video.domain.MediaTvSeason;
import com.omninest.modules.video.domain.MediaTvSeries;
import com.omninest.modules.video.domain.MediaVideoItem;
import com.omninest.modules.video.dto.MovieDtos.CastMemberDto;
import com.omninest.modules.video.dto.MovieDtos.CrewMemberDto;
import com.omninest.modules.video.dto.MovieDtos.ScrapeCandidateDto;
import com.omninest.modules.video.event.MediaScrapeRequestedEvent;
import com.omninest.modules.video.repository.MediaMovieRepository;
import com.omninest.modules.video.repository.MediaTvEpisodeRepository;
import com.omninest.modules.video.repository.MediaTvSeasonRepository;
import com.omninest.modules.video.repository.MediaTvSeriesRepository;
import com.omninest.modules.video.repository.MediaVideoItemRepository;
import com.omninest.modules.file.service.DerivedAssetRequest;
import com.omninest.modules.file.service.DerivedAssetStorageService;
import com.omninest.modules.file.service.FileLifecycleGuard;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.notification.service.NotificationService;
import com.omninest.modules.task.service.TaskRecordService;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.Mockito;
import org.springframework.context.ApplicationEventPublisher;

/**
 * 影视元数据刮削任务执行测试。
 *
 * @author OmniNest
 */
class MovieScrapeExecutionServiceTest {
    private static final UUID TASK_ID = UUID.fromString("40000000-0000-0000-0000-000000000001");
    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID FILE_ID = UUID.fromString("30000000-0000-0000-0000-000000000001");
    private static final UUID SERIES_ID = UUID.fromString("50000000-0000-0000-0000-000000000001");

    private final MediaRuntimeConfigService configService = Mockito.mock(MediaRuntimeConfigService.class);
    private final MediaVideoItemRepository videoItemRepository = Mockito.mock(MediaVideoItemRepository.class);
    private final TaskRecordService taskRecordService = Mockito.mock(TaskRecordService.class);
    private final MetadataProvider provider = Mockito.mock(MetadataProvider.class);
    private final ContentAssetService contentAssetService = Mockito.mock(ContentAssetService.class);
    private final ApplicationEventPublisher applicationEventPublisher = Mockito.mock(ApplicationEventPublisher.class);
    private final MediaTvSeriesRepository tvSeriesRepository = Mockito.mock(MediaTvSeriesRepository.class);
    private final MediaTvSeasonRepository tvSeasonRepository = Mockito.mock(MediaTvSeasonRepository.class);
    private final MediaMovieRepository movieRepository = Mockito.mock(MediaMovieRepository.class);
    private final MediaTvEpisodeRepository episodeRepository = Mockito.mock(MediaTvEpisodeRepository.class);
    private final NotificationService notificationService = Mockito.mock(NotificationService.class);
    private final DerivedAssetStorageService derivedAssetStorageService = Mockito.mock(DerivedAssetStorageService.class);
    private final MediaSyncEventService syncEventService = Mockito.mock(MediaSyncEventService.class);
    private final FileLifecycleGuard fileLifecycleGuard = Mockito.mock(FileLifecycleGuard.class);
    private final ReadThroughCache readThroughCache = Mockito.mock(ReadThroughCache.class);
    private final MovieScrapeExecutionService executionService =
            new MovieScrapeExecutionService(
                    configService,
                    videoItemRepository,
                    taskRecordService,
                    List.of(provider),
                    contentAssetService,
                    applicationEventPublisher,
                    tvSeriesRepository,
                    tvSeasonRepository,
                    movieRepository,
                    episodeRepository,
                    notificationService,
                    derivedAssetStorageService,
                    syncEventService,
                    fileLifecycleGuard,
                    readThroughCache
            );

    @BeforeEach
    void setUpTaskClaim() {
        when(taskRecordService.claimForExecution(any(UUID.class), any(String.class))).thenReturn(true);
    }

    @Test
    void completesTaskWithoutMetadataLookupWhenProvidersDisabled() {
        when(configService.metadataProvidersEnabled()).thenReturn(false);
        MediaVideoItem item = pendingItem();
        when(videoItemRepository.findByOwnerUserIdAndFileNodeId(OWNER_ID, FILE_ID)).thenReturn(Optional.of(item));

        executionService.execute(event("Inception", 2010));

        assertThat(item.getMetadataStatus()).isEqualTo("PENDING");
        verify(provider, never()).search(any());
        verify(taskRecordService).markCompleted(eq(TASK_ID), argThat(result ->
                "元数据提供器未启用".equals(result.get("message"))));
    }

    @Test
    void createsMediaMovieAndLinksToVideoItemOnSuccessfulScrape() {
        when(configService.metadataProvidersEnabled()).thenReturn(true);
        MediaVideoItem item = pendingItem();
        when(videoItemRepository.findByOwnerUserIdAndFileNodeId(OWNER_ID, FILE_ID)).thenReturn(Optional.of(item));
        when(provider.providerName()).thenReturn("LOCAL");
        ScrapeCandidateDto candidate = new ScrapeCandidateDto(
                "LOCAL",
                "local-inception-2010",
                "Inception",
                null,
                null,
                2010,
                "A dream within a dream.",
                null,
                null,
                null,
                null,
                null,
                null, null, null, null, null, null, null, null, null, null, null
        );
        when(provider.search(new FileNameGuess("Inception", 2010, null, null))).thenReturn(List.of(candidate));
        when(movieRepository.findByTmdbIdAndOwnerUserId(any(), eq(OWNER_ID))).thenReturn(Optional.empty());
        when(movieRepository.save(any(MediaMovie.class))).thenAnswer(invocation -> {
            MediaMovie m = invocation.getArgument(0);
            m.setId(UUID.randomUUID());
            return m;
        });
        when(contentAssetService.syncPrimaryMovieAssets(any(), eq(OWNER_ID), eq(candidate)))
                .thenReturn(new ContentAssetService.MovieAssetResult(null, null));

        executionService.execute(event("Inception", 2010));

        assertThat(item.getMovieId()).isNotNull();
        assertThat(item.getMetadataStatus()).isEqualTo("MATCHED");
        verify(movieRepository, atLeast(2)).save(any(MediaMovie.class));
        verify(contentAssetService).syncPrimaryMovieAssets(any(), eq(OWNER_ID), eq(candidate));
        verify(taskRecordService).markCompleted(eq(TASK_ID), argThat(result ->
                "local-inception-2010".equals(result.get("externalId"))));
    }

    @Test
    void storesSeriesCastAndCrewWithProfileAssetsOnEpisodeScrape() {
        when(configService.metadataProvidersEnabled()).thenReturn(true);
        MediaVideoItem item = pendingEpisodeItem();
        when(videoItemRepository.findByOwnerUserIdAndFileNodeId(OWNER_ID, FILE_ID)).thenReturn(Optional.of(item));
        when(provider.providerName()).thenReturn("TMDB");
        UUID profileFileNodeId = UUID.fromString("70000000-0000-0000-0000-000000000001");
        when(derivedAssetStorageService.storeRemote(any(DerivedAssetRequest.class))).thenReturn(profileFileNodeId);

        ScrapeCandidateDto candidate = new ScrapeCandidateDto(
                "TMDB",
                "1399",
                "示例剧集",
                null,
                null,
                2019,
                "剧情简介",
                "https://image.tmdb.org/t/p/w500/poster.jpg",
                "https://image.tmdb.org/t/p/w1280/backdrop.jpg",
                null,
                8.5,
                null,
                List.of("剧情"),
                List.of(
                        new CastMemberDto("演员一", "角色一", "https://image.tmdb.org/t/p/w185/cast-1.jpg", 0),
                        new CastMemberDto("演员二", "角色二", "https://image.tmdb.org/t/p/w185/cast-2.jpg", 1)),
                List.of(new CrewMemberDto("导演一", "Director", "Directing", "https://image.tmdb.org/t/p/w185/crew.jpg")),
                100,
                "TV-MA",
                null,
                null,
                "en",
                List.of(),
                List.of(),
                List.of()
        );
        when(provider.search(new FileNameGuess("示例剧集", 2019, null, null))).thenReturn(List.of(candidate));
        when(tvSeriesRepository.findByTmdbIdAndOwnerUserId(1399, OWNER_ID)).thenReturn(Optional.empty());
        when(tvSeriesRepository.save(any(MediaTvSeries.class))).thenAnswer(invocation -> {
            MediaTvSeries series = invocation.getArgument(0);
            series.setId(SERIES_ID);
            return series;
        });
        when(contentAssetService.syncPrimarySeriesAssets(any(), any(), eq(candidate)))
                .thenReturn(new ContentAssetService.SeriesAssetResult(null, null));
        when(tvSeasonRepository.save(any(MediaTvSeason.class))).thenAnswer(invocation -> invocation.getArgument(0));
        when(episodeRepository.save(any(MediaTvEpisode.class))).thenAnswer(invocation -> invocation.getArgument(0));

        executionService.execute(event("示例剧集", 2019));

        ArgumentCaptor<MediaTvSeries> seriesCaptor = ArgumentCaptor.forClass(MediaTvSeries.class);
        verify(tvSeriesRepository, atLeast(2)).save(seriesCaptor.capture());
        MediaTvSeries saved = seriesCaptor.getValue();
        assertThat(saved.getCastMembers()).hasSize(2);
        assertThat(saved.getCastMembers()).allSatisfy(member ->
                assertThat(member)
                        .containsEntry("profileFileId", profileFileNodeId.toString()));
        assertThat(saved.getCrewMembers()).hasSize(1);
        assertThat(saved.getCrewMembers().get(0))
                .containsEntry("name", "导演一")
                .containsEntry("profileFileId", profileFileNodeId.toString());
        // 旧实现按显示名命名：等长中文名折叠为同一路径，导致多名演员共用一张头像。
        ArgumentCaptor<DerivedAssetRequest> requestCaptor = ArgumentCaptor.forClass(DerivedAssetRequest.class);
        verify(derivedAssetStorageService, times(3)).storeRemote(requestCaptor.capture());
        List<String> profileFileNames = requestCaptor.getAllValues().stream()
                .map(DerivedAssetRequest::fileName)
                .toList();
        assertThat(profileFileNames).doesNotHaveDuplicates();
        assertThat(profileFileNames).anySatisfy(name ->
                assertThat(name).matches("[0-9a-f]{8}_演员一\\.jpg"));
        assertThat(profileFileNames).anySatisfy(name ->
                assertThat(name).matches("[0-9a-f]{8}_演员二\\.jpg"));
        verify(derivedAssetStorageService, times(3)).storeRemote(any(DerivedAssetRequest.class));
        assertThat(item.getMetadataStatus()).isEqualTo("MATCHED");
    }

    private MediaScrapeRequestedEvent event(String title, Integer year) {
        return new MediaScrapeRequestedEvent(TASK_ID, OWNER_ID, FILE_ID, title, year, null, null, false);
    }

    private MediaVideoItem pendingItem() {
        MediaVideoItem item = new MediaVideoItem();
        item.setId(UUID.fromString("60000000-0000-0000-0000-000000000001"));
        item.setOwnerUserId(OWNER_ID);
        item.setFileNodeId(FILE_ID);
        item.setMediaType("MOVIE");
        item.setMetadataStatus("PENDING");
        return item;
    }

    private MediaVideoItem pendingEpisodeItem() {
        MediaVideoItem item = pendingItem();
        item.setMediaType("EPISODE");
        item.setSeasonNumber(1);
        item.setEpisodeNumber(1);
        return item;
    }
}
