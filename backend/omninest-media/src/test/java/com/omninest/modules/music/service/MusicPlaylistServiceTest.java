package com.omninest.modules.music.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.error.BusinessException;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.music.domain.MusicPlaylist;
import com.omninest.modules.music.domain.MusicPlaylistItem;
import com.omninest.modules.music.domain.MusicTrack;
import com.omninest.modules.music.dto.MusicDtos.CreatePlaylistRequest;
import com.omninest.modules.music.dto.MusicDtos.MusicTrackDto;
import com.omninest.modules.music.dto.MusicDtos.PlaylistItemsRequest;
import com.omninest.modules.music.dto.MusicDtos.UpdatePlaylistRequest;
import com.omninest.modules.music.repository.MusicPlaylistItemRepository;
import com.omninest.modules.music.repository.MusicPlaylistRepository;
import com.omninest.modules.music.repository.MusicTrackRepository;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;

class MusicPlaylistServiceTest {
    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID PLAYLIST_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");
    private static final UUID FIRST_TRACK_ID = UUID.fromString("30000000-0000-0000-0000-000000000001");
    private static final UUID SECOND_TRACK_ID = UUID.fromString("30000000-0000-0000-0000-000000000002");

    private final MusicPlaylistRepository playlistRepository = mock(MusicPlaylistRepository.class);
    private final MusicPlaylistItemRepository playlistItemRepository =
            mock(MusicPlaylistItemRepository.class);
    private final MusicTrackRepository trackRepository = mock(MusicTrackRepository.class);
    private final MusicLibraryService musicLibraryService = mock(MusicLibraryService.class);
    private final MusicCoverService musicCoverService = mock(MusicCoverService.class);
    private final MusicCoverRetentionService coverRetentionService = mock(MusicCoverRetentionService.class);
    private final MediaSyncEventService syncEventService = mock(MediaSyncEventService.class);
    private final MusicPlaylistService playlistService =
            new MusicPlaylistService(
                    playlistRepository,
                    playlistItemRepository,
                    trackRepository,
                    musicLibraryService,
                    musicCoverService,
                    coverRetentionService,
                    syncEventService
            );

    @Test
    void createPlaylistPersistsValidatedCustomCover() {
        UUID coverFileId = UUID.fromString("40000000-0000-0000-0000-000000000001");
        when(playlistRepository.save(any(MusicPlaylist.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        var result = playlistService.create(
                OWNER_ID,
                new CreatePlaylistRequest("Road Trip", "Night songs", coverFileId)
        );

        verify(musicCoverService).validateOwnedCover(OWNER_ID, coverFileId);
        assertThat(result.coverFileId()).isEqualTo(coverFileId);
    }

    @Test
    void updateRejectsNonCustomPlaylist() {
        MusicPlaylist playlist = new MusicPlaylist();
        playlist.setId(PLAYLIST_ID);
        playlist.setOwnerUserId(OWNER_ID);
        playlist.setName("Daily Mix");
        playlist.setPlaylistType("LEGACY");
        when(playlistRepository.findByIdAndOwnerUserId(PLAYLIST_ID, OWNER_ID))
                .thenReturn(Optional.of(playlist));

        assertThatThrownBy(() -> playlistService.update(
                OWNER_ID,
                PLAYLIST_ID,
                new UpdatePlaylistRequest("Changed", null, null)
        )).isInstanceOf(BusinessException.class)
                .hasMessageContaining("自建歌单");
    }

    @Test
    void addItemsRejectsNonCustomPlaylist() {
        MusicPlaylist playlist = new MusicPlaylist();
        playlist.setId(PLAYLIST_ID);
        playlist.setOwnerUserId(OWNER_ID);
        playlist.setName("Daily Mix");
        playlist.setPlaylistType("LEGACY");
        when(playlistRepository.findByIdAndOwnerUserId(PLAYLIST_ID, OWNER_ID))
                .thenReturn(Optional.of(playlist));

        assertThatThrownBy(() -> playlistService.addItems(
                OWNER_ID,
                PLAYLIST_ID,
                new PlaylistItemsRequest(List.of(FIRST_TRACK_ID))
        )).isInstanceOf(BusinessException.class)
                .hasMessageContaining("自建歌单");
    }

    @Test
    void playlistTracksPreservesPlaylistItemOrder() {
        MusicPlaylist playlist = new MusicPlaylist();
        playlist.setId(PLAYLIST_ID);
        playlist.setOwnerUserId(OWNER_ID);
        playlist.setName("Road Trip");

        MusicPlaylistItem first = item(FIRST_TRACK_ID, 0);
        MusicPlaylistItem second = item(SECOND_TRACK_ID, 1);
        MusicTrack firstTrack = track(FIRST_TRACK_ID, "First");
        MusicTrack secondTrack = track(SECOND_TRACK_ID, "Second");

        when(playlistRepository.findByIdAndOwnerUserId(PLAYLIST_ID, OWNER_ID)).thenReturn(Optional.of(playlist));
        when(playlistItemRepository.findByOwnerUserIdAndPlaylistIdOrderBySortOrderAscCreatedAtAsc(OWNER_ID, PLAYLIST_ID))
                .thenReturn(List.of(first, second));
        when(trackRepository.findByOwnerUserIdAndIdIn(OWNER_ID, List.of(FIRST_TRACK_ID, SECOND_TRACK_ID)))
                .thenReturn(List.of(secondTrack, firstTrack));
        when(musicLibraryService.toTrackDto(firstTrack, false)).thenReturn(dto(FIRST_TRACK_ID, "First"));
        when(musicLibraryService.toTrackDto(secondTrack, false)).thenReturn(dto(SECOND_TRACK_ID, "Second"));

        var result = playlistService.playlistTracks(OWNER_ID, PLAYLIST_ID);

        assertThat(result).extracting(MusicTrackDto::id).containsExactly(FIRST_TRACK_ID, SECOND_TRACK_ID);
    }

    @Test
    void playlistsUsesFirstTrackCoverWhenPlaylistHasNoCustomCover() {
        MusicPlaylist playlist = new MusicPlaylist();
        playlist.setId(PLAYLIST_ID);
        playlist.setOwnerUserId(OWNER_ID);
        playlist.setName("Road Trip");
        MusicPlaylistItem first = item(FIRST_TRACK_ID, 0);
        MusicTrack firstTrack = track(FIRST_TRACK_ID, "First");

        when(playlistRepository.findByOwnerUserIdOrderByUpdatedAtDesc(OWNER_ID))
                .thenReturn(List.of(playlist));
        when(playlistItemRepository.countByOwnerUserIdAndPlaylistIdIn(OWNER_ID, List.of(PLAYLIST_ID)))
                .thenReturn(List.<Object[]>of(new Object[]{PLAYLIST_ID, 1L}));
        when(playlistItemRepository.findOrderedByOwnerAndPlaylistIds(OWNER_ID, List.of(PLAYLIST_ID)))
                .thenReturn(List.of(first));
        when(trackRepository.findByOwnerUserIdAndIdIn(
                eq(OWNER_ID),
                anyList()
        )).thenReturn(List.of(firstTrack));
        when(musicLibraryService.toTrackDto(firstTrack, false))
                .thenReturn(dto(FIRST_TRACK_ID, "First", "https://example.com/cover.jpg"));

        var result = playlistService.playlists(OWNER_ID);

        assertThat(result).singleElement()
                .satisfies(value -> assertThat(value.coverUrl()).isEqualTo("https://example.com/cover.jpg"));
    }

    @Test
    void removeItemsReturnsCoverFromNewFirstTrack() {
        MusicPlaylist playlist = new MusicPlaylist();
        playlist.setId(PLAYLIST_ID);
        playlist.setOwnerUserId(OWNER_ID);
        playlist.setName("Road Trip");
        MusicPlaylistItem remaining = item(SECOND_TRACK_ID, 1);
        MusicTrack secondTrack = track(SECOND_TRACK_ID, "Second");

        when(playlistRepository.findByIdAndOwnerUserId(PLAYLIST_ID, OWNER_ID))
                .thenReturn(Optional.of(playlist));
        when(playlistItemRepository.countByOwnerUserIdAndPlaylistId(OWNER_ID, PLAYLIST_ID))
                .thenReturn(1L);
        when(playlistItemRepository.findByOwnerUserIdAndPlaylistIdOrderBySortOrderAscCreatedAtAsc(
                OWNER_ID,
                PLAYLIST_ID
        )).thenReturn(List.of(remaining));
        when(trackRepository.findByIdAndOwnerUserId(SECOND_TRACK_ID, OWNER_ID))
                .thenReturn(Optional.of(secondTrack));
        when(musicLibraryService.toTrackDto(secondTrack, false))
                .thenReturn(dto(SECOND_TRACK_ID, "Second", "https://example.com/second.jpg"));

        var result = playlistService.removeItems(
                OWNER_ID,
                PLAYLIST_ID,
                new PlaylistItemsRequest(List.of(FIRST_TRACK_ID))
        );

        assertThat(result.trackCount()).isEqualTo(1);
        assertThat(result.coverUrl()).isEqualTo("https://example.com/second.jpg");
    }

    private MusicPlaylistItem item(UUID trackId, int sortOrder) {
        MusicPlaylistItem item = new MusicPlaylistItem();
        item.setOwnerUserId(OWNER_ID);
        item.setPlaylistId(PLAYLIST_ID);
        item.setTrackId(trackId);
        item.setSortOrder(sortOrder);
        item.setCreatedAt(Instant.parse("2026-05-21T10:00:00Z").plusSeconds(sortOrder));
        return item;
    }

    private MusicTrack track(UUID id, String title) {
        MusicTrack track = new MusicTrack();
        track.setId(id);
        track.setOwnerUserId(OWNER_ID);
        track.setTitle(title);
        return track;
    }

    private MusicTrackDto dto(UUID id, String title) {
        return dto(id, title, null);
    }

    private MusicTrackDto dto(UUID id, String title, String coverUrl) {
        return new MusicTrackDto(
                id,
                UUID.randomUUID(),
                title,
                "Unknown Artist",
                "Unknown Album",
                null,
                "flac",
                null,
                null,
                null,
                null,
                null,
                null,
                coverUrl,
                false,
                Instant.parse("2026-05-21T10:00:00Z")
        );
    }
}
