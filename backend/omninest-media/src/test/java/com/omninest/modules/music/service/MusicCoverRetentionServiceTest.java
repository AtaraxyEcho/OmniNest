package com.omninest.modules.music.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyCollection;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.modules.file.service.DerivedAssetStorageService;
import com.omninest.modules.music.domain.MusicAlbum;
import com.omninest.modules.music.domain.MusicPlaylist;
import com.omninest.modules.music.domain.MusicTrack;
import com.omninest.modules.music.repository.MusicAlbumRepository;
import com.omninest.modules.music.repository.MusicArtistRepository;
import com.omninest.modules.music.repository.MusicPlaylistRepository;
import com.omninest.modules.music.repository.MusicTrackRepository;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

/**
 * 校验封面资产回收只在完全无业务引用时执行，并且始终连缩略图一起删除。
 */
class MusicCoverRetentionServiceTest {

    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID COVER_ID = UUID.fromString("20000000-0000-0000-0000-000000000002");
    private static final UUID OTHER_COVER_ID = UUID.fromString("20000000-0000-0000-0000-000000000003");
    private static final UUID THUMBNAIL_ID = UUID.fromString("30000000-0000-0000-0000-000000000004");

    private final MusicTrackRepository trackRepository = mock(MusicTrackRepository.class);
    private final MusicAlbumRepository albumRepository = mock(MusicAlbumRepository.class);
    private final MusicArtistRepository artistRepository = mock(MusicArtistRepository.class);
    private final MusicPlaylistRepository playlistRepository = mock(MusicPlaylistRepository.class);
    private final MusicCoverThumbnailService coverThumbnailService = mock(MusicCoverThumbnailService.class);
    private final DerivedAssetStorageService derivedAssetStorageService =
            mock(DerivedAssetStorageService.class);
    private final MusicCoverRetentionService service = new MusicCoverRetentionService(
            trackRepository,
            albumRepository,
            artistRepository,
            playlistRepository,
            coverThumbnailService,
            derivedAssetStorageService
    );

    @BeforeEach
    void unreferenceEverything() {
        when(trackRepository.findByOwnerUserIdAndCoverFileIdIn(eq(OWNER_ID), anyCollection()))
                .thenReturn(List.of());
        when(albumRepository.findByOwnerUserIdAndCoverFileIdIn(eq(OWNER_ID), anyCollection()))
                .thenReturn(List.of());
        when(artistRepository.findByOwnerUserIdAndAvatarFileIdIn(eq(OWNER_ID), anyCollection()))
                .thenReturn(List.of());
        when(playlistRepository.findByOwnerUserIdAndCoverFileIdIn(eq(OWNER_ID), anyCollection()))
                .thenReturn(List.of());
        when(coverThumbnailService.findThumbnailFileId(OWNER_ID, COVER_ID))
                .thenReturn(Optional.of(THUMBNAIL_ID));
    }

    @Test
    void unreferencedCoverIsDeletedTogetherWithItsThumbnail() {
        service.releaseUnreferenced(OWNER_ID, COVER_ID);

        assertThat(deletedBatch()).containsExactlyInAnyOrder(THUMBNAIL_ID, COVER_ID);
    }

    @Test
    void coverStillUsedByAnotherTrackIsKept() {
        MusicTrack other = new MusicTrack();
        other.setCoverFileId(COVER_ID);
        when(trackRepository.findByOwnerUserIdAndCoverFileIdIn(eq(OWNER_ID), anyCollection()))
                .thenReturn(List.of(other));

        service.releaseUnreferenced(OWNER_ID, COVER_ID);

        verify(derivedAssetStorageService, never()).deleteOwnedBatch(eq(OWNER_ID), anyCollection());
    }

    @Test
    void sharedAlbumCoverIsKeptEvenWhenTheTrackReleasedIt() {
        MusicAlbum album = new MusicAlbum();
        album.setCoverFileId(COVER_ID);
        when(albumRepository.findByOwnerUserIdAndCoverFileIdIn(eq(OWNER_ID), anyCollection()))
                .thenReturn(List.of(album));

        service.releaseUnreferenced(OWNER_ID, COVER_ID);

        verify(derivedAssetStorageService, never()).deleteOwnedBatch(eq(OWNER_ID), anyCollection());
    }

    @Test
    void batchReleaseOnlyDeletesTheUnreferencedEntries() {
        MusicPlaylist playlist = new MusicPlaylist();
        playlist.setCoverFileId(OTHER_COVER_ID);
        when(playlistRepository.findByOwnerUserIdAndCoverFileIdIn(eq(OWNER_ID), anyCollection()))
                .thenAnswer(invocation -> {
                    Collection<UUID> ids = invocation.getArgument(1);
                    return ids.contains(OTHER_COVER_ID) ? List.of(playlist) : List.of();
                });
        when(coverThumbnailService.findThumbnailFileId(OWNER_ID, OTHER_COVER_ID))
                .thenReturn(Optional.empty());

        service.releaseUnreferenced(OWNER_ID, List.of(COVER_ID, OTHER_COVER_ID));

        assertThat(deletedBatch()).containsExactlyInAnyOrder(THUMBNAIL_ID, COVER_ID);
    }

    @Test
    void nullOwnerAndEmptyInputSkipEveryQuery() {
        service.releaseUnreferenced(null, COVER_ID);
        service.releaseUnreferenced(OWNER_ID, List.of());
        service.releaseUnreferenced(OWNER_ID, (UUID) null);

        verify(trackRepository, never()).findByOwnerUserIdAndCoverFileIdIn(any(), anyCollection());
        verify(derivedAssetStorageService, never()).deleteOwnedBatch(any(), anyCollection());
    }

    private Collection<UUID> deletedBatch() {
        ArgumentCaptor<Collection<UUID>> captor = ArgumentCaptor.captor();
        verify(derivedAssetStorageService).deleteOwnedBatch(eq(OWNER_ID), captor.capture());
        return captor.getValue();
    }
}
