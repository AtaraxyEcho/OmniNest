package com.omninest.modules.media.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyCollection;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.modules.music.domain.MusicAlbum;
import com.omninest.modules.music.domain.MusicTrack;
import com.omninest.modules.music.repository.MusicAlbumRepository;
import com.omninest.modules.music.repository.MusicTrackRepository;
import com.omninest.modules.reader.domain.ReaderItem;
import com.omninest.modules.reader.repository.ReaderItemRepository;
import com.omninest.modules.video.domain.MediaMovie;
import com.omninest.modules.video.domain.MediaTvSeason;
import com.omninest.modules.video.domain.MediaVideoItem;
import com.omninest.modules.video.repository.MediaMovieRepository;
import com.omninest.modules.video.repository.MediaTvSeasonRepository;
import com.omninest.modules.video.repository.MediaTvSeriesRepository;
import com.omninest.modules.video.repository.MediaVideoItemRepository;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;

/**
 * 媒体封面反查端口实现测试：三条解析链的回退关系与缓存命中。
 *
 * @author OmniNest
 */
class MediaCoverDirectoryImplTest {

    private final MusicTrackRepository musicTrackRepository = Mockito.mock(MusicTrackRepository.class);
    private final MusicAlbumRepository musicAlbumRepository = Mockito.mock(MusicAlbumRepository.class);
    private final MediaVideoItemRepository videoItemRepository = Mockito.mock(MediaVideoItemRepository.class);
    private final MediaMovieRepository movieRepository = Mockito.mock(MediaMovieRepository.class);
    private final MediaTvSeasonRepository seasonRepository = Mockito.mock(MediaTvSeasonRepository.class);
    private final MediaTvSeriesRepository seriesRepository = Mockito.mock(MediaTvSeriesRepository.class);
    private final ReaderItemRepository readerItemRepository = Mockito.mock(ReaderItemRepository.class);

    private final MediaCoverDirectoryImpl directory = new MediaCoverDirectoryImpl(
            musicTrackRepository,
            musicAlbumRepository,
            videoItemRepository,
            movieRepository,
            seasonRepository,
            seriesRepository,
            readerItemRepository
    );

    private static UUID id(int seed) {
        return UUID.fromString("10000000-0000-0000-0000-0000000000%02d".formatted(seed));
    }

    @Test
    void musicTrackCoverWinsOverAlbumFallback() {
        UUID file = id(1);
        UUID trackCover = id(20);
        UUID albumCover = id(21);
        MusicTrack track = new MusicTrack();
        track.setFileNodeId(file);
        track.setCoverFileId(trackCover);
        track.setAlbumId(id(30));
        when(musicTrackRepository.findByFileNodeIdIn(anyCollection())).thenReturn(List.of(track));
        MusicAlbum album = new MusicAlbum();
        album.setId(track.getAlbumId());
        album.setCoverFileId(albumCover);
        when(musicAlbumRepository.findAllById(anyCollection())).thenReturn(List.of(album));

        Map<UUID, UUID> covers = directory.resolveCoverFileIds(id(99), List.of(file));

        assertThat(covers).containsEntry(file, trackCover);
    }

    @Test
    void trackWithoutCoverFallsBackToAlbumCover() {
        UUID file = id(2);
        UUID albumCover = id(22);
        MusicTrack track = new MusicTrack();
        track.setFileNodeId(file);
        track.setCoverFileId(null);
        track.setAlbumId(id(31));
        when(musicTrackRepository.findByFileNodeIdIn(anyCollection())).thenReturn(List.of(track));
        MusicAlbum album = new MusicAlbum();
        album.setId(track.getAlbumId());
        album.setCoverFileId(albumCover);
        when(musicAlbumRepository.findAllById(anyCollection())).thenReturn(List.of(album));

        assertThat(directory.resolveCoverFileIds(id(99), List.of(file)))
                .containsEntry(file, albumCover);
    }

    @Test
    void videoSeasonPosterWinsOverMovieAndSeries() {
        UUID file = id(3);
        UUID seasonPoster = id(40);
        UUID moviePoster = id(41);
        UUID seriesPoster = id(42);
        MediaVideoItem item = new MediaVideoItem();
        item.setFileNodeId(file);
        item.setMovieId(id(50));
        item.setSeasonId(id(51));
        item.setSeriesId(id(52));
        when(videoItemRepository.findByOwnerUserIdAndFileNodeIdIn(any(), anyCollection()))
                .thenReturn(List.of(item));
        MediaMovie movie = new MediaMovie();
        movie.setId(item.getMovieId());
        movie.setPosterFileId(moviePoster);
        when(movieRepository.findAllById(anyCollection())).thenReturn(List.of(movie));
        MediaTvSeason season = new MediaTvSeason();
        season.setId(item.getSeasonId());
        season.setPosterFileId(seasonPoster);
        when(seasonRepository.findAllById(anyCollection())).thenReturn(List.of(season));

        assertThat(directory.resolveCoverFileIds(id(99), List.of(file)))
                .containsEntry(file, seasonPoster);
    }

    @Test
    void readerItemCoverResolved() {
        UUID file = id(4);
        UUID readerCover = id(60);
        ReaderItem item = new ReaderItem();
        item.setFileNodeId(file);
        item.setCoverFileId(readerCover);
        when(readerItemRepository.findByFileNodeIdIn(anyCollection())).thenReturn(List.of(item));

        assertThat(directory.resolveCoverFileIds(id(99), List.of(file)))
                .containsEntry(file, readerCover);
    }

    @Test
    void secondCallHitsCacheWithoutRepositories() {
        UUID file = id(5);
        UUID cover = id(61);
        ReaderItem item = new ReaderItem();
        item.setFileNodeId(file);
        item.setCoverFileId(cover);
        when(readerItemRepository.findByFileNodeIdIn(anyCollection())).thenReturn(List.of(item));

        directory.resolveCoverFileIds(id(99), List.of(file));
        Map<UUID, UUID> second = directory.resolveCoverFileIds(id(99), List.of(file));

        assertThat(second).containsEntry(file, cover);
        verify(readerItemRepository, Mockito.times(1)).findByFileNodeIdIn(anyCollection());
    }

    @Test
    void emptyAndNullInputsReturnEmpty() {
        assertThat(directory.resolveCoverFileIds(id(99), List.of())).isEmpty();
        assertThat(directory.resolveCoverFileIds(null, List.of(id(6)))).isEmpty();
    }
}
