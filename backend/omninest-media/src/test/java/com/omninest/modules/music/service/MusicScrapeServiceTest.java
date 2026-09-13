package com.omninest.modules.music.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doNothing;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.modules.task.domain.TaskStatus;
import com.omninest.common.cache.ReadThroughCache;
import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.file.dto.FileDownloadUrlDto;
import com.omninest.modules.file.service.FileQueryService;
import com.omninest.modules.file.service.FileDeletionService;
import com.omninest.modules.file.service.DerivedAssetStorageService;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.music.config.MusicLibraryProperties;
import com.omninest.modules.music.domain.MusicAlbum;
import com.omninest.modules.music.domain.MusicArtist;
import com.omninest.modules.music.domain.MusicScanJob;
import com.omninest.modules.music.domain.MusicTrack;
import com.omninest.modules.music.dto.MusicDtos.MusicScrapeApplyRequest;
import com.omninest.modules.music.dto.MusicDtos.MusicScrapeCandidateDto;
import com.omninest.modules.music.event.MusicScrapeEvent;
import com.omninest.modules.music.repository.MusicAlbumRepository;
import com.omninest.modules.music.repository.MusicArtistRepository;
import com.omninest.modules.music.repository.MusicFavoriteRepository;
import com.omninest.modules.music.repository.MusicPlayHistoryRepository;
import com.omninest.modules.music.repository.MusicScanJobRepository;
import com.omninest.modules.music.repository.MusicTrackRepository;
import com.omninest.modules.notification.service.NotificationService;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import java.time.Instant;
import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

class MusicScrapeServiceTest {
    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID TRACK_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");

    private final MusicTrackRepository trackRepository = mock(MusicTrackRepository.class);
    private final MusicAlbumRepository albumRepository = mock(MusicAlbumRepository.class);
    private final MusicArtistRepository artistRepository = mock(MusicArtistRepository.class);
    private final MusicFavoriteRepository favoriteRepository = mock(MusicFavoriteRepository.class);
    private final MusicPlayHistoryRepository playHistoryRepository = mock(MusicPlayHistoryRepository.class);
    private final FileQueryService fileQueryService = mock(FileQueryService.class);
    private final FileDeletionService fileDeletionService = mock(FileDeletionService.class);
    private final ReadThroughCache readThroughCache = mock(ReadThroughCache.class);
    private final MediaSyncEventService syncEventService = mock(MediaSyncEventService.class);
    private final MusicLibraryProperties musicLibraryProperties = new MusicLibraryProperties();
    private final MusicLibraryService musicLibraryService = new MusicLibraryService(
            trackRepository,
            albumRepository,
            artistRepository,
            favoriteRepository,
            playHistoryRepository,
            fileDeletionService,
            fileQueryService,
            readThroughCache,
            syncEventService,
            musicLibraryProperties
    );
    private final MusicScanJobRepository scanJobRepository = mock(MusicScanJobRepository.class);
    private final MusicCatalogService catalogService = mock(MusicCatalogService.class);
    private final MusicMetadataProvider metadataProvider = mock(MusicMetadataProvider.class);
    private final NotificationService notificationService =
            mock(NotificationService.class);
    private final DerivedAssetStorageService derivedAssetStorageService =
            mock(DerivedAssetStorageService.class);
    private final TaskRecordService taskRecordService = mock(TaskRecordService.class);
    private final TaskDispatchService taskDispatchService = mock(TaskDispatchService.class);
    private final MusicScrapeService scrapeService = new MusicScrapeService(
            trackRepository,
            favoriteRepository,
            scanJobRepository,
            musicLibraryService,
            notificationService,
            catalogService,
            derivedAssetStorageService,
            List.of(metadataProvider),
            taskRecordService,
            taskDispatchService
    );

    @BeforeEach
    void setUpTaskClaim() {
        when(taskRecordService.claimForExecution(any(UUID.class), any(String.class))).thenReturn(true);
    }

    @Test
    void scrapeLibraryCreatesUnifiedSystemTaskAndQueuesWorkerEvent() {
        when(scanJobRepository.save(any(MusicScanJob.class))).thenAnswer(invocation -> invocation.getArgument(0));

        var dto = scrapeService.scrapeLibrary(OWNER_ID, true);

        assertThat(dto.status()).isEqualTo(TaskStatus.QUEUED.getValue());
        assertThat(dto.message()).isEqualTo("MusicBrainz 刮削任务已排队");
        verify(taskRecordService).createQueuedTask(
                eq(dto.id()),
                eq(OWNER_ID),
                eq("MUSIC_SCRAPE"),
                eq(QueueNames.MUSIC_SCRAPE_ROUTING_KEY),
                any()
        );
        verify(taskDispatchService).enqueue(
                eq(dto.id()),
                eq(QueueNames.TASK_EXCHANGE),
                eq(QueueNames.MUSIC_SCRAPE_ROUTING_KEY),
                any(MusicScrapeEvent.class));
    }

    @Test
    void applyCandidateUpdatesTrackAndRefreshesStatistics() {
        MusicTrack track = new MusicTrack();
        track.setId(TRACK_ID);
        track.setOwnerUserId(OWNER_ID);
        track.setFileNodeId(UUID.fromString("30000000-0000-0000-0000-000000000001"));
        track.setArtistId(UUID.fromString("40000000-0000-0000-0000-000000000001"));
        track.setAlbumId(UUID.fromString("50000000-0000-0000-0000-000000000001"));
        track.setTitle("Fallback Title");
        track.setArtistName("Fallback Artist");
        track.setAlbumTitle("Fallback Album");
        track.setProviderMetadata(new LinkedHashMap<>());
        when(trackRepository.findByIdAndOwnerUserId(TRACK_ID, OWNER_ID)).thenReturn(Optional.of(track));
        when(trackRepository.save(any(MusicTrack.class))).thenAnswer(invocation -> invocation.getArgument(0));
        when(favoriteRepository.findByOwnerUserIdAndTrackId(OWNER_ID, TRACK_ID)).thenReturn(Optional.empty());

        MusicArtist artist = new MusicArtist();
        artist.setId(UUID.fromString("40000000-0000-0000-0000-000000000002"));
        artist.setOwnerUserId(OWNER_ID);
        artist.setName("Omni Band");
        when(catalogService.resolveArtist(eq(OWNER_ID), eq("Omni Band"), eq("artist-1"), any()))
                .thenReturn(artist);
        MusicAlbum album = new MusicAlbum();
        album.setId(UUID.fromString("50000000-0000-0000-0000-000000000002"));
        album.setOwnerUserId(OWNER_ID);
        album.setTitle("City Lights");
        when(catalogService.resolveAlbum(
                eq(OWNER_ID),
                eq("City Lights"),
                eq("Omni Band"),
                eq(LocalDate.parse("2024-01-02")),
                eq("rel-1"),
                eq("rg-1"),
                any()
        )).thenReturn(album);
        doNothing().when(catalogService).refreshStatistics(any(), any(), any(), any());
        UUID coverFileId = UUID.fromString("60000000-0000-0000-0000-000000000001");
        when(derivedAssetStorageService.storeRemote(any())).thenReturn(coverFileId);
        when(fileQueryService.createDownloadUrl(OWNER_ID, coverFileId))
                .thenReturn(new FileDownloadUrlDto(
                        coverFileId,
                        "cover.jpg",
                        "https://minio.example/cover.jpg",
                        Instant.now().plusSeconds(900)
                ));

        MusicScrapeApplyRequest request = new MusicScrapeApplyRequest(
                "MusicBrainz",
                "rec-1",
                "Night Drive",
                "Omni Band",
                "City Lights",
                LocalDate.parse("2024-01-02"),
                245,
                1,
                1,
                "https://coverartarchive.org/release/rel-1/front-500",
                92,
                null,
                new LinkedHashMap<>(Map.of(
                        "musicbrainzRecordingId", "rec-1",
                        "musicbrainzReleaseId", "rel-1",
                        "musicbrainzReleaseGroupId", "rg-1",
                        "musicbrainzArtistId", "artist-1"
                )),
                new LinkedHashMap<>(Map.of(
                        "provider", "MusicBrainz",
                        "coverUrl", "https://coverartarchive.org/release/rel-1/front-500"
                ))
        );

        var dto = scrapeService.applyCandidate(OWNER_ID, TRACK_ID, request);

        assertThat(dto.title()).isEqualTo("Night Drive");
        assertThat(dto.artistName()).isEqualTo("Omni Band");
        assertThat(dto.albumTitle()).isEqualTo("City Lights");
        // 封面已下载到 MinIO，coverUrl 应为本地下载 URL（coverFileId 优先于外部 URL）
        assertThat(dto.coverUrl()).isEqualTo("https://minio.example/cover.jpg");
        assertThat(track.getCoverFileId()).isEqualTo(coverFileId);
        assertThat(track.getMetadataStatus()).isEqualTo("MATCHED");
        assertThat(track.getExternalIds()).containsEntry("musicbrainzRecordingId", "rec-1");
    }
}
