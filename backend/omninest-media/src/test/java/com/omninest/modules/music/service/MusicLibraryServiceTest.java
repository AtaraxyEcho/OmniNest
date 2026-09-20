package com.omninest.modules.music.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;

import com.omninest.common.cache.ReadThroughCache;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.service.FileDeletionService;
import com.omninest.modules.file.service.FilePurgeOrigin;
import com.omninest.modules.file.service.FileQueryService;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.music.config.MusicLibraryProperties;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.music.domain.MusicAlbum;
import com.omninest.modules.music.domain.MusicArtist;
import com.omninest.modules.music.domain.MusicPlayHistory;
import com.omninest.modules.music.domain.MusicTrack;
import com.omninest.modules.music.dto.MusicDtos.RecordMusicPlayHistoryRequest;
import com.omninest.modules.music.repository.MusicAlbumRepository;
import com.omninest.modules.music.repository.MusicArtistRepository;
import com.omninest.modules.music.repository.MusicFavoriteRepository;
import com.omninest.modules.music.repository.MusicPlayHistoryRepository;
import com.omninest.modules.music.repository.MusicTrackRepository;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.mockito.ArgumentCaptor;
import org.mockito.ArgumentMatchers;
import org.junit.jupiter.api.Test;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Sort;

/**
 * 本地音乐曲库服务测试。
 *
 * @author OmniNest
 */
class MusicLibraryServiceTest {
    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID TRACK_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");
    private static final UUID FILE_NODE_ID = UUID.fromString("30000000-0000-0000-0000-000000000001");
    private static final UUID COVER_FILE_ID = UUID.fromString("40000000-0000-0000-0000-000000000001");

    private final MusicTrackRepository trackRepository = mock(MusicTrackRepository.class);
    private final MusicAlbumRepository albumRepository = mock(MusicAlbumRepository.class);
    private final MusicArtistRepository artistRepository = mock(MusicArtistRepository.class);
    private final MusicFavoriteRepository favoriteRepository = mock(MusicFavoriteRepository.class);
    private final MusicPlayHistoryRepository playHistoryRepository = mock(MusicPlayHistoryRepository.class);
    private final FileDeletionService fileDeletionService = mock(FileDeletionService.class);
    private final FileQueryService fileQueryService = mock(FileQueryService.class);
    private final ReadThroughCache readThroughCache = mock(ReadThroughCache.class);
    private final MediaSyncEventService syncEventService = mock(MediaSyncEventService.class);
    private final MusicLibraryProperties musicLibraryProperties = new MusicLibraryProperties();
    private final MusicLibraryService libraryService = new MusicLibraryService(
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

    @Test
    void albumTracksReturnsOwnerScopedTracks() {
        UUID albumId = UUID.fromString("50000000-0000-0000-0000-000000000001");
        MusicAlbum album = new MusicAlbum();
        album.setId(albumId);
        album.setOwnerUserId(OWNER_ID);
        when(albumRepository.findByIdAndOwnerUserId(albumId, OWNER_ID)).thenReturn(Optional.of(album));
        when(trackRepository.findAlbumTracks(OWNER_ID, albumId)).thenReturn(List.of(track()));

        var tracks = libraryService.albumTracks(OWNER_ID, albumId);

        assertThat(tracks).hasSize(1);
        assertThat(tracks.get(0).id()).isEqualTo(TRACK_ID);
    }

    @Test
    void albumTracksRejectsAlbumOfOtherOwner() {
        UUID albumId = UUID.fromString("50000000-0000-0000-0000-000000000001");
        when(albumRepository.findByIdAndOwnerUserId(albumId, OWNER_ID)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> libraryService.albumTracks(OWNER_ID, albumId))
                .isInstanceOf(BusinessException.class)
                .extracting("errorCode")
                .isEqualTo(ErrorCode.MEDIA_NOT_FOUND);
    }

    @Test
    void artistTracksReturnsOwnerScopedTracks() {
        UUID artistId = UUID.fromString("60000000-0000-0000-0000-000000000001");
        MusicArtist artist = new MusicArtist();
        artist.setId(artistId);
        artist.setOwnerUserId(OWNER_ID);
        when(artistRepository.findByIdAndOwnerUserId(artistId, OWNER_ID)).thenReturn(Optional.of(artist));
        when(trackRepository.findArtistTracks(OWNER_ID, artistId)).thenReturn(List.of(track()));

        var tracks = libraryService.artistTracks(OWNER_ID, artistId);

        assertThat(tracks).hasSize(1);
        assertThat(tracks.get(0).id()).isEqualTo(TRACK_ID);
    }

    private MusicTrack track() {
        MusicTrack track = new MusicTrack();
        track.setId(TRACK_ID);
        track.setOwnerUserId(OWNER_ID);
        track.setFileNodeId(FILE_NODE_ID);
        track.setTitle("Night Drive");
        track.setProviderMetadata(new LinkedHashMap<>());
        return track;
    }

    @Test
    void deleteTrackPermanentlyDeletesLinkedFile() {
        MusicTrack track = new MusicTrack();
        track.setId(TRACK_ID);
        track.setOwnerUserId(OWNER_ID);
        track.setFileNodeId(FILE_NODE_ID);
        when(trackRepository.findByIdAndOwnerUserId(TRACK_ID, OWNER_ID)).thenReturn(Optional.of(track));

        libraryService.deleteTrack(OWNER_ID, TRACK_ID);

        verify(fileDeletionService).deletePermanently(
                eq(OWNER_ID),
                eq(FILE_NODE_ID),
                eq(false),
                ArgumentMatchers.any(FilePurgeOrigin.class),
                isNull()
        );
    }

    @Test
    void trackDtoUsesProviderMetadataCoverUrlWhenNoFileCoverExists() {
        MusicTrack track = new MusicTrack();
        track.setId(TRACK_ID);
        track.setOwnerUserId(OWNER_ID);
        track.setFileNodeId(FILE_NODE_ID);
        track.setTitle("Night Drive");
        track.setArtistName("Omni Band");
        track.setAlbumTitle("City Lights");
        track.setProviderMetadata(new LinkedHashMap<>());
        track.getProviderMetadata().put("coverUrl", "https://example.com/cover.jpg");

        var dto = libraryService.toTrackDto(track, false);

        assertThat(dto.coverUrl()).isEqualTo("https://example.com/cover.jpg");
    }

    @Test
    void trackDtoPrefersEmbeddedCoverOverExternalProviderUrl() {
        MusicTrack track = new MusicTrack();
        track.setId(TRACK_ID);
        track.setOwnerUserId(OWNER_ID);
        track.setFileNodeId(FILE_NODE_ID);
        track.setTitle("Night Drive");
        track.setProviderMetadata(new LinkedHashMap<>());
        track.getProviderMetadata().put("coverDataUrl", "data:image/jpeg;base64,embedded");
        track.getProviderMetadata().put("coverUrl", "https://coverartarchive.org/release/test/front-500");

        var dto = libraryService.toTrackDto(track, false);

        assertThat(dto.coverUrl()).isEqualTo("data:image/jpeg;base64,embedded");
    }

    @Test
    void trackDtoUsesStableApiPathForLocalCover() {
        MusicTrack track = new MusicTrack();
        track.setId(TRACK_ID);
        track.setOwnerUserId(OWNER_ID);
        track.setFileNodeId(FILE_NODE_ID);
        track.setCoverFileId(COVER_FILE_ID);
        track.setTitle("Night Drive");

        var dto = libraryService.toTrackDto(track, false);

        assertThat(dto.coverUrl()).isEqualTo("/api/v1/music/covers/" + COVER_FILE_ID);
    }

    @Test
    void trackDtoLocalCoverTakesPriorityOverProviderMetadata() {
        MusicTrack track = new MusicTrack();
        track.setId(TRACK_ID);
        track.setOwnerUserId(OWNER_ID);
        track.setFileNodeId(FILE_NODE_ID);
        track.setCoverFileId(COVER_FILE_ID);
        track.setTitle("Night Drive");
        track.setProviderMetadata(new LinkedHashMap<>());
        track.getProviderMetadata().put("coverUrl", "https://example.com/cover.jpg");

        var dto = libraryService.toTrackDto(track, false);

        assertThat(dto.coverUrl()).isEqualTo("/api/v1/music/covers/" + COVER_FILE_ID);
    }

    @Test
    void playHistoryPagesWithinRetentionWindow() {
        MusicPlayHistory history = new MusicPlayHistory();
        history.setOwnerUserId(OWNER_ID);
        history.setPlayableKey("local:" + TRACK_ID);
        history.setTitle("Night Drive");
        history.setPlayedAt(Instant.now());
        var pageable = PageRequest.of(0, 50);
        when(playHistoryRepository.findByOwnerUserIdAndPlayedAtGreaterThanEqualOrderByPlayedAtDesc(
                eq(OWNER_ID), ArgumentMatchers.any(Instant.class), eq(pageable)))
                .thenReturn(new PageImpl<>(List.of(history), pageable, 1));

        var result = libraryService.playHistory(OWNER_ID, 0, 50);

        assertThat(result.getContent()).hasSize(1);
        assertThat(result.getContent().getFirst().title()).isEqualTo("Night Drive");
        assertThat(result.getContent().getFirst().playableKey()).isEqualTo("local:" + TRACK_ID);
        assertThat(result.getTotalElements()).isEqualTo(1);
    }

    @Test
    void tracksPagingFallsBackToDefaultSortForUnknownField() {
        MusicTrack track = new MusicTrack();
        track.setId(TRACK_ID);
        track.setOwnerUserId(OWNER_ID);
        track.setFileNodeId(FILE_NODE_ID);
        track.setTitle("Night Drive");
        var pageable = PageRequest.of(2, 50, Sort.by(Sort.Direction.ASC, "title"));
        when(trackRepository.findTracksVisibleToUser(eq(OWNER_ID), eq(SpaceType.SHARED), eq(pageable)))
                .thenReturn(new PageImpl<>(List.of(track), pageable, 151));

        var result = libraryService.tracks(OWNER_ID, 2, 50, "ownerUserId,desc");

        assertThat(result.getContent()).hasSize(1);
        assertThat(result.getTotalElements()).isEqualTo(151);
        verify(trackRepository).findTracksVisibleToUser(OWNER_ID, SpaceType.SHARED, pageable);
    }

    @Test
    void tracksPagingAppliesWhitelistedDescendingSort() {
        var pageable = PageRequest.of(0, 100, Sort.by(Sort.Direction.DESC, "updatedAt"));
        when(trackRepository.findTracksVisibleToUser(eq(OWNER_ID), eq(SpaceType.SHARED), eq(pageable)))
                .thenReturn(new PageImpl<>(List.of(), pageable, 0));

        var result = libraryService.tracks(OWNER_ID, 0, 100, "updatedAt,desc");

        assertThat(result.getTotalElements()).isZero();
        verify(trackRepository).findTracksVisibleToUser(OWNER_ID, SpaceType.SHARED, pageable);
    }

    @Test
    void searchUsesMultiFieldRepositoryQueryWithStableLimit() {
        MusicTrack track = new MusicTrack();
        track.setId(TRACK_ID);
        track.setOwnerUserId(OWNER_ID);
        track.setFileNodeId(FILE_NODE_ID);
        track.setTitle("Night Drive");
        track.setArtistName("Omni Band");
        track.setAlbumTitle("City Lights");
        PageRequest pageRequest = PageRequest.of(0, 20);
        when(trackRepository.searchByOwnerUserId(OWNER_ID, "Omni", pageRequest))
                .thenReturn(List.of(track));

        var result = libraryService.search(OWNER_ID, "  Omni  ");

        assertThat(result.tracks()).hasSize(1);
        assertThat(result.tracks().getFirst().artistName()).isEqualTo("Omni Band");
        verify(trackRepository).searchByOwnerUserId(OWNER_ID, "Omni", pageRequest);
    }

    @Test
    void recordsOnlineTrackWithTypedKeyAndDisplaySnapshot() {
        RecordMusicPlayHistoryRequest request = new RecordMusicPlayHistoryRequest(
                "online:netease:song-1",
                0,
                "Cloud Song",
                "Cloud Artist",
                "Cloud Album",
                "https://example.com/cloud.jpg",
                180,
                null
        );

        libraryService.recordPlayHistory(OWNER_ID, request);

        ArgumentCaptor<MusicPlayHistory> captor = ArgumentCaptor.forClass(MusicPlayHistory.class);
        verify(playHistoryRepository).save(captor.capture());
        MusicPlayHistory history = captor.getValue();
        assertThat(history.getTrackId()).isNull();
        assertThat(history.getPlayableKey()).isEqualTo("online:netease:song-1");
        assertThat(history.getTitle()).isEqualTo("Cloud Song");
        verify(playHistoryRepository).deleteExpiredHistory(
                ArgumentMatchers.eq(OWNER_ID),
                ArgumentMatchers.any(Instant.class)
        );
    }

    @Test
    void recentItemsRestoreOnlineTrackSnapshot() {
        MusicPlayHistory history = new MusicPlayHistory();
        history.setOwnerUserId(OWNER_ID);
        history.setPlayableKey("online:qq:song-2");
        history.setPlatform("qq");
        history.setExternalSongId("song-2");
        history.setTitle("QQ Song");
        history.setArtistName("QQ Artist");
        history.setCoverUrl("https://example.com/qq.jpg");
        history.setPlayedAt(Instant.parse("2026-07-12T01:00:00Z"));
        when(playHistoryRepository
                .findTop50ByOwnerUserIdAndPlayedAtGreaterThanEqualOrderByPlayedAtDesc(
                        ArgumentMatchers.eq(OWNER_ID),
                        ArgumentMatchers.any(Instant.class)
                ))
                .thenReturn(List.of(history));
        when(trackRepository.findByOwnerUserIdAndIdIn(OWNER_ID, List.of())).thenReturn(List.of());

        var recent = libraryService.recentItems(OWNER_ID);

        assertThat(recent).hasSize(1);
        assertThat(recent.getFirst().playableKey()).isEqualTo("online:qq:song-2");
        assertThat(recent.getFirst().onlineTrack().title()).isEqualTo("QQ Song");
    }
}
