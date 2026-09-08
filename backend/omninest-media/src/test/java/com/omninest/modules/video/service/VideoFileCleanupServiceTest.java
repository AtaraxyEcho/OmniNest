package com.omninest.modules.video.service;

import com.omninest.common.cache.ReadThroughCache;
import com.omninest.common.sync.SyncScope;
import com.omninest.modules.file.event.FileNodesSoftDeletedEvent;
import com.omninest.modules.file.service.PurgeContext;
import com.omninest.modules.media.domain.MediaPlaybackType;
import com.omninest.modules.media.service.MediaPlaybackCleanupService;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.video.domain.ContentAsset;
import com.omninest.modules.video.domain.MediaVideoItem;
import com.omninest.modules.video.repository.ContentAssetRepository;
import com.omninest.modules.video.repository.MediaMovieRepository;
import com.omninest.modules.video.repository.MediaNfoExportRepository;
import com.omninest.modules.video.repository.MediaSeriesFavoriteRepository;
import com.omninest.modules.video.repository.MediaSubtitleTrackRepository;
import com.omninest.modules.video.repository.MediaTvEpisodeRepository;
import com.omninest.modules.video.repository.MediaTvSeasonRepository;
import com.omninest.modules.video.repository.MediaTvSeriesRepository;
import com.omninest.modules.video.repository.MediaVideoCollectionItemRepository;
import com.omninest.modules.video.repository.MediaVideoCollectionRepository;
import com.omninest.modules.video.repository.MediaVideoFavoriteRepository;
import com.omninest.modules.video.repository.MediaVideoItemRepository;
import com.omninest.modules.video.repository.MediaWatchHistoryRepository;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;

/**
 * 影视文件关联数据清理服务测试。
 *
 * @author OmniNest
 */
class VideoFileCleanupServiceTest {
    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID FILE_NODE_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");
    private static final UUID VIDEO_ITEM_ID = UUID.fromString("30000000-0000-0000-0000-000000000001");
    private static final UUID ASSET_FILE_ID = UUID.fromString("40000000-0000-0000-0000-000000000001");

    private final MediaVideoItemRepository videoItemRepository =
            Mockito.mock(MediaVideoItemRepository.class);
    private final MediaPlaybackCleanupService playbackCleanupService =
            Mockito.mock(MediaPlaybackCleanupService.class);
    private final MediaWatchHistoryRepository watchHistoryRepository =
            Mockito.mock(MediaWatchHistoryRepository.class);
    private final MediaVideoFavoriteRepository videoFavoriteRepository =
            Mockito.mock(MediaVideoFavoriteRepository.class);
    private final MediaVideoCollectionItemRepository collectionItemRepository =
            Mockito.mock(MediaVideoCollectionItemRepository.class);
    private final MediaSubtitleTrackRepository subtitleTrackRepository =
            Mockito.mock(MediaSubtitleTrackRepository.class);
    private final MediaNfoExportRepository nfoExportRepository =
            Mockito.mock(MediaNfoExportRepository.class);
    private final ContentAssetRepository contentAssetRepository = Mockito.mock(ContentAssetRepository.class);
    private final MediaMovieRepository movieRepository = Mockito.mock(MediaMovieRepository.class);
    private final MediaTvEpisodeRepository tvEpisodeRepository = Mockito.mock(MediaTvEpisodeRepository.class);
    private final MediaTvSeasonRepository tvSeasonRepository = Mockito.mock(MediaTvSeasonRepository.class);
    private final MediaTvSeriesRepository tvSeriesRepository = Mockito.mock(MediaTvSeriesRepository.class);
    private final MediaSeriesFavoriteRepository seriesFavoriteRepository =
            Mockito.mock(MediaSeriesFavoriteRepository.class);
    private final MediaVideoCollectionRepository videoCollectionRepository =
            Mockito.mock(MediaVideoCollectionRepository.class);
    private final MediaSyncEventService syncEventService = Mockito.mock(MediaSyncEventService.class);
    private final ReadThroughCache readThroughCache = Mockito.mock(ReadThroughCache.class);
    private final VideoFileCleanupService service = new VideoFileCleanupService(
            videoItemRepository,
            playbackCleanupService,
            watchHistoryRepository,
            videoFavoriteRepository,
            collectionItemRepository,
            subtitleTrackRepository,
            nfoExportRepository,
            contentAssetRepository,
            movieRepository,
            tvEpisodeRepository,
            tvSeasonRepository,
            tvSeriesRepository,
            seriesFavoriteRepository,
            videoCollectionRepository,
            syncEventService,
            readThroughCache
    );

    @Test
    void hardDeleteRemovesOwnedVideoAndDerivedAssets() {
        MediaVideoItem videoItem = new MediaVideoItem();
        videoItem.setId(VIDEO_ITEM_ID);
        videoItem.setOwnerUserId(OWNER_ID);
        videoItem.setFileNodeId(FILE_NODE_ID);
        ContentAsset contentAsset = Mockito.mock(ContentAsset.class);
        Mockito.when(contentAsset.getFileNodeId()).thenReturn(ASSET_FILE_ID);
        Mockito.when(videoItemRepository.findByFileNodeIdIn(List.of(FILE_NODE_ID)))
                .thenReturn(List.of(videoItem));
        Mockito.when(contentAssetRepository.findAllByOwnerUserIdAndResourceTypeAndResourceIdIn(
                Mockito.eq(OWNER_ID),
                Mockito.anyString(),
                Mockito.eq(List.of(VIDEO_ITEM_ID))
        )).thenReturn(List.of(contentAsset));

        service.finalizePurge(purgeContext());

        Mockito.verify(playbackCleanupService).deleteOwned(
                OWNER_ID,
                MediaPlaybackType.VIDEO,
                List.of(VIDEO_ITEM_ID.toString())
        );
        Mockito.verify(contentAssetRepository).deleteAll(List.of(contentAsset));
        Mockito.verify(videoItemRepository).deleteAllInBatch(List.of(videoItem));
    }

    @Test
    void softDeletePreservesVideoRowsAndUserAssociations() {
        service.handleFileNodesSoftDeleted(new FileNodesSoftDeletedEvent(
                OWNER_ID,
                List.of(FILE_NODE_ID),
                Instant.now()
        ));

        Mockito.verifyNoInteractions(playbackCleanupService, watchHistoryRepository, videoFavoriteRepository);
        Mockito.verify(videoItemRepository, Mockito.never()).deleteAllInBatch(Mockito.anyList());
    }

    @Test
    void visibilityChangeInvalidatesAffectedVideoOwner() {
        MediaVideoItem videoItem = new MediaVideoItem();
        videoItem.setOwnerUserId(OWNER_ID);
        Mockito.when(videoItemRepository.findByFileNodeIdIn(List.of(FILE_NODE_ID)))
                .thenReturn(List.of(videoItem));

        service.invalidateFileVisibility(List.of(FILE_NODE_ID));

        Mockito.verify(syncEventService).invalidate(
                OWNER_ID,
                SyncScope.VIDEO,
                "VIDEO_LIBRARY",
                Map.of("reason", "FILE_VISIBILITY_CHANGED")
        );
    }

    private PurgeContext purgeContext() {
        return new PurgeContext(UUID.randomUUID(), OWNER_ID, FILE_NODE_ID, List.of(FILE_NODE_ID));
    }
}
