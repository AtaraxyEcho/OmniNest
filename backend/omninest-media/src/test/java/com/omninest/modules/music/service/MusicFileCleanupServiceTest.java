package com.omninest.modules.music.service;

import com.omninest.common.cache.ReadThroughCache;
import com.omninest.common.sync.SyncScope;
import com.omninest.modules.file.event.FileNodesSoftDeletedEvent;
import com.omninest.modules.file.service.PurgeContext;
import com.omninest.modules.media.domain.MediaPlaybackType;
import com.omninest.modules.media.service.MediaPlaybackCleanupService;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.music.domain.MusicTrack;
import com.omninest.modules.music.repository.MusicAlbumRepository;
import com.omninest.modules.music.repository.MusicArtistRepository;
import com.omninest.modules.music.repository.MusicFavoriteRepository;
import com.omninest.modules.music.repository.MusicPlayHistoryRepository;
import com.omninest.modules.music.repository.MusicPlaylistItemRepository;
import com.omninest.modules.music.repository.MusicPlaylistRepository;
import com.omninest.modules.music.repository.MusicTrackRepository;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;

/**
 * 音乐文件关联数据清理服务测试。
 *
 * @author OmniNest
 */
class MusicFileCleanupServiceTest {
    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID FILE_NODE_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");
    private static final UUID TRACK_ID = UUID.fromString("30000000-0000-0000-0000-000000000001");

    private final MusicTrackRepository trackRepository = Mockito.mock(MusicTrackRepository.class);
    private final MediaPlaybackCleanupService playbackCleanupService =
            Mockito.mock(MediaPlaybackCleanupService.class);
    private final MusicFavoriteRepository favoriteRepository = Mockito.mock(MusicFavoriteRepository.class);
    private final MusicPlayHistoryRepository playHistoryRepository =
            Mockito.mock(MusicPlayHistoryRepository.class);
    private final MusicPlaylistItemRepository playlistItemRepository =
            Mockito.mock(MusicPlaylistItemRepository.class);
    private final MusicAlbumRepository albumRepository = Mockito.mock(MusicAlbumRepository.class);
    private final MusicArtistRepository artistRepository = Mockito.mock(MusicArtistRepository.class);
    private final MusicPlaylistRepository playlistRepository = Mockito.mock(MusicPlaylistRepository.class);
    private final MediaSyncEventService syncEventService = Mockito.mock(MediaSyncEventService.class);
    private final ReadThroughCache readThroughCache = Mockito.mock(ReadThroughCache.class);
    private final MusicFileCleanupService service = new MusicFileCleanupService(
            trackRepository,
            playbackCleanupService,
            favoriteRepository,
            playHistoryRepository,
            playlistItemRepository,
            albumRepository,
            artistRepository,
            playlistRepository,
            syncEventService,
            readThroughCache
    );

    @Test
    void hardDeleteRemovesOwnedTrackAssociations() {
        MusicTrack track = track();
        Mockito.when(trackRepository.findByFileNodeIdIn(List.of(FILE_NODE_ID)))
                .thenReturn(List.of(track));

        service.finalizePurge(purgeContext());

        List<String> musicKeys = List.of("local:" + TRACK_ID);
        Mockito.verify(playbackCleanupService).deleteOwned(
                OWNER_ID,
                MediaPlaybackType.MUSIC,
                musicKeys
        );
        Mockito.verify(favoriteRepository).deleteByOwnerUserIdAndTrackIdIn(OWNER_ID, List.of(TRACK_ID));
        Mockito.verify(playHistoryRepository).deleteByOwnerUserIdAndTrackIdIn(OWNER_ID, List.of(TRACK_ID));
        Mockito.verify(playlistItemRepository).deleteByOwnerUserIdAndTrackIdIn(OWNER_ID, List.of(TRACK_ID));
        Mockito.verify(trackRepository).deleteAllInBatch(List.of(track));
    }

    @Test
    void softDeletePreservesMusicRowsAndUserAssociations() {
        service.handleFileNodesSoftDeleted(new FileNodesSoftDeletedEvent(
                OWNER_ID,
                List.of(FILE_NODE_ID),
                Instant.now()
        ));

        Mockito.verifyNoInteractions(playbackCleanupService);
        Mockito.verify(trackRepository, Mockito.never()).deleteAllInBatch(Mockito.anyList());
    }

    @Test
    void visibilityChangeInvalidatesAffectedMusicOwner() {
        Mockito.when(trackRepository.findByFileNodeIdIn(List.of(FILE_NODE_ID)))
                .thenReturn(List.of(track()));

        service.invalidateFileVisibility(List.of(FILE_NODE_ID));

        Mockito.verify(syncEventService).invalidate(
                OWNER_ID,
                SyncScope.MUSIC,
                "MUSIC_LIBRARY",
                Map.of("reason", "FILE_VISIBILITY_CHANGED")
        );
    }

    private MusicTrack track() {
        MusicTrack track = new MusicTrack();
        track.setId(TRACK_ID);
        track.setOwnerUserId(OWNER_ID);
        track.setFileNodeId(FILE_NODE_ID);
        return track;
    }

    private PurgeContext purgeContext() {
        return new PurgeContext(UUID.randomUUID(), OWNER_ID, FILE_NODE_ID, List.of(FILE_NODE_ID));
    }
}
