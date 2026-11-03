package com.omninest.modules.video.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.modules.file.dto.LocalMediaScanEntry;
import com.omninest.modules.video.domain.MediaLibraryType;
import com.omninest.modules.video.domain.MediaMovie;
import com.omninest.modules.video.domain.MediaTvEpisode;
import com.omninest.modules.video.domain.MediaTvSeason;
import com.omninest.modules.video.domain.MediaTvSeries;
import com.omninest.modules.video.domain.MediaType;
import com.omninest.modules.video.domain.MediaVideoItem;
import com.omninest.modules.video.domain.SeriesType;
import com.omninest.modules.video.domain.VideoLibrarySource;
import com.omninest.modules.video.repository.MediaMovieRepository;
import com.omninest.modules.video.repository.MediaTvEpisodeRepository;
import com.omninest.modules.video.repository.MediaTvSeasonRepository;
import com.omninest.modules.video.repository.MediaTvSeriesRepository;
import com.omninest.modules.video.repository.MediaVideoItemRepository;
import java.time.LocalDate;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

class LocalMediaLibraryClassifierTest {
    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID SOURCE_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");
    private static final UUID FILE_ID = UUID.fromString("30000000-0000-0000-0000-000000000001");
    private static final UUID SERIES_ID = UUID.fromString("40000000-0000-0000-0000-000000000001");
    private static final UUID SEASON_ID = UUID.fromString("50000000-0000-0000-0000-000000000001");
    private static final UUID EPISODE_ID = UUID.fromString("60000000-0000-0000-0000-000000000001");
    private static final UUID MOVIE_ID = UUID.fromString("70000000-0000-0000-0000-000000000001");

    private final MediaVideoItemRepository videoItemRepository = mock(MediaVideoItemRepository.class);
    private final MediaMovieRepository movieRepository = mock(MediaMovieRepository.class);
    private final MediaTvSeriesRepository seriesRepository = mock(MediaTvSeriesRepository.class);
    private final MediaTvSeasonRepository seasonRepository = mock(MediaTvSeasonRepository.class);
    private final MediaTvEpisodeRepository episodeRepository = mock(MediaTvEpisodeRepository.class);
    private final LocalMediaLibraryClassifier classifier = new LocalMediaLibraryClassifier(
            new SimpleFileNameParser(),
            videoItemRepository,
            movieRepository,
            seriesRepository,
            seasonRepository,
            episodeRepository
    );

    @BeforeEach
    void configureSavedEntities() {
        when(seriesRepository.save(any(MediaTvSeries.class))).thenAnswer(invocation -> {
            MediaTvSeries value = invocation.getArgument(0);
            if (value.getId() == null) {
                value.setId(SERIES_ID);
            }
            return value;
        });
        when(movieRepository.save(any(MediaMovie.class))).thenAnswer(invocation -> {
            MediaMovie value = invocation.getArgument(0);
            if (value.getId() == null) {
                value.setId(MOVIE_ID);
            }
            return value;
        });
        when(seasonRepository.save(any(MediaTvSeason.class))).thenAnswer(invocation -> {
            MediaTvSeason value = invocation.getArgument(0);
            if (value.getId() == null) {
                value.setId(SEASON_ID);
            }
            return value;
        });
        when(episodeRepository.save(any(MediaTvEpisode.class))).thenAnswer(invocation -> {
            MediaTvEpisode value = invocation.getArgument(0);
            if (value.getId() == null) {
                value.setId(EPISODE_ID);
            }
            return value;
        });
        when(videoItemRepository.save(any(MediaVideoItem.class))).thenAnswer(invocation -> invocation.getArgument(0));
    }

    @Test
    void previewsRepresentativeFilesFromRealMediaLibraryFixture() {
        VideoLibrarySource anime = source(MediaLibraryType.ANIME, "Anime");

        LocalMediaLibraryClassifier.PreviewIdentity numbered = classifier.preview(
                anime,
                "Anime/Aotu World Ⅲ/01.mp4",
                "01.mp4"
        );
        LocalMediaLibraryClassifier.PreviewIdentity special = classifier.preview(
                anime,
                "Anime/Aotu World Ⅲ/SP1.mp4",
                "SP1.mp4"
        );
        LocalMediaLibraryClassifier.PreviewIdentity explicit = classifier.preview(
                anime,
                "Anime/葬送的芙莉莲 第二季/Frieren.Beyond.Journeys.End.S02E01.mkv",
                "Frieren.Beyond.Journeys.End.S02E01.mkv"
        );

        assertThat(numbered.groupTitle()).isEqualTo("Aotu World");
        assertThat(numbered.seasonNumber()).isEqualTo(3);
        assertThat(numbered.episodeNumber()).isEqualTo(1);
        assertThat(special.seasonNumber()).isZero();
        assertThat(special.episodeNumber()).isEqualTo(1);
        assertThat(explicit.seasonNumber()).isEqualTo(2);
        assertThat(explicit.episodeNumber()).isEqualTo(1);
    }

    @Test
    void mixedRootChoosesClassifierFromFirstDirectory() {
        VideoLibrarySource root = source(MediaLibraryType.ROOT, ".");

        LocalMediaLibraryClassifier.PreviewIdentity anime = classifier.preview(
                root,
                "Anime/Aotu World Ⅲ/01.mp4",
                "01.mp4"
        );
        LocalMediaLibraryClassifier.PreviewIdentity series = classifier.preview(
                root,
                "TV Series/Foundation/S01E01.mkv",
                "S01E01.mkv"
        );
        LocalMediaLibraryClassifier.PreviewIdentity movie = classifier.preview(
                root,
                "Movie/Dune Part Two (2024)/Dune Part Two (2024).mkv",
                "Dune Part Two (2024).mkv"
        );

        assertThat(anime.candidateType()).isEqualTo("EPISODE");
        assertThat(series.candidateType()).isEqualTo("EPISODE");
        assertThat(movie.candidateType()).isEqualTo("MOVIE");
    }

    @Test
    void classifiesMovieFolderAsOneMovieEntityWithoutMetadataLookup() {
        VideoLibrarySource source = source(MediaLibraryType.MOVIE, "Movies");
        when(movieRepository.findFirstByOwnerUserIdAndLibrarySourceIdAndTitleAndReleaseDateOrderByCreatedAtAsc(
                OWNER_ID, SOURCE_ID, "Dune Part Two", LocalDate.of(2024, 1, 1)))
                .thenReturn(Optional.empty());
        when(videoItemRepository.findByOwnerUserIdAndFileNodeId(OWNER_ID, FILE_ID)).thenReturn(Optional.empty());

        var outcome = classifier.classify(
                OWNER_ID,
                source,
                new LocalMediaScanEntry(
                        FILE_ID,
                        "Movies/Dune.Part.Two.2024/Dune.Part.Two.2024.2160p.mkv",
                        "Dune.Part.Two.2024.2160p.mkv"
                )
        );

        assertThat(outcome).isEqualTo(LocalMediaLibraryClassifier.ClassificationOutcome.CREATED);
        ArgumentCaptor<MediaMovie> movie = ArgumentCaptor.forClass(MediaMovie.class);
        verify(movieRepository).save(movie.capture());
        assertThat(movie.getValue().getTitle()).isEqualTo("Dune Part Two");
        assertThat(movie.getValue().getLibrarySourceId()).isEqualTo(SOURCE_ID);
    }

    @Test
    void classifiesTvEpisodeIntoSeriesSeasonAndEpisodeWithoutMetadataLookup() {
        VideoLibrarySource source = source(MediaLibraryType.TV_SERIES, "TV Series");
        when(seriesRepository.findFirstByOwnerUserIdAndLibrarySourceIdAndTitleIgnoreCaseOrderByCreatedAtAsc(
                OWNER_ID, SOURCE_ID, "Foundation")).thenReturn(Optional.empty());
        when(seasonRepository.findByOwnerUserIdAndSeriesIdAndSeasonNumber(OWNER_ID, SERIES_ID, 2))
                .thenReturn(Optional.empty());
        when(episodeRepository.findByOwnerUserIdAndSeriesIdAndSeasonNumberAndEpisodeNumber(
                OWNER_ID, SERIES_ID, 2, 3)).thenReturn(Optional.empty());
        when(videoItemRepository.findByOwnerUserIdAndFileNodeId(OWNER_ID, FILE_ID)).thenReturn(Optional.empty());

        var outcome = classifier.classify(
                OWNER_ID,
                source,
                new LocalMediaScanEntry(
                        FILE_ID,
                        "TV Series/Foundation/Season 02/Foundation.S02E03.mkv",
                        "Foundation.S02E03.mkv"
                )
        );

        assertThat(outcome).isEqualTo(LocalMediaLibraryClassifier.ClassificationOutcome.CREATED);
        ArgumentCaptor<MediaVideoItem> item = ArgumentCaptor.forClass(MediaVideoItem.class);
        verify(videoItemRepository).save(item.capture());
        assertThat(item.getValue().getMediaType()).isEqualTo(MediaType.EPISODE.getValue());
        assertThat(item.getValue().getSeriesId()).isEqualTo(SERIES_ID);
        assertThat(item.getValue().getSeasonNumber()).isEqualTo(2);
        assertThat(item.getValue().getEpisodeNumber()).isEqualTo(3);
    }

    @Test
    void classifiesAnimeNumericEpisodeAndPreservesAnimeSeriesType() {
        VideoLibrarySource source = source(MediaLibraryType.ANIME, "Anime");
        when(seriesRepository.findFirstByOwnerUserIdAndLibrarySourceIdAndTitleIgnoreCaseOrderByCreatedAtAsc(
                OWNER_ID, SOURCE_ID, "Frieren")).thenReturn(Optional.empty());
        when(seasonRepository.findByOwnerUserIdAndSeriesIdAndSeasonNumber(OWNER_ID, SERIES_ID, 1))
                .thenReturn(Optional.empty());
        when(episodeRepository.findByOwnerUserIdAndSeriesIdAndSeasonNumberAndEpisodeNumber(
                OWNER_ID, SERIES_ID, 1, 12)).thenReturn(Optional.empty());
        when(videoItemRepository.findByOwnerUserIdAndFileNodeId(OWNER_ID, FILE_ID)).thenReturn(Optional.empty());

        classifier.classify(
                OWNER_ID,
                source,
                new LocalMediaScanEntry(
                        FILE_ID,
                        "Anime/Frieren/[Subs] Frieren - 12 [1080p].mkv",
                        "[Subs] Frieren - 12 [1080p].mkv"
                )
        );

        ArgumentCaptor<MediaTvSeries> series = ArgumentCaptor.forClass(MediaTvSeries.class);
        verify(seriesRepository).save(series.capture());
        assertThat(series.getValue().getSeriesType()).isEqualTo(SeriesType.ANIME.getValue());
        assertThat(series.getValue().getTitle()).isEqualTo("Frieren");
    }

    @Test
    void classifiesUnicodeRomanSeasonSuffixFromSeriesDirectory() {
        VideoLibrarySource source = source(MediaLibraryType.ANIME, "Anime");
        when(seriesRepository.findFirstByOwnerUserIdAndLibrarySourceIdAndTitleIgnoreCaseOrderByCreatedAtAsc(
                OWNER_ID, SOURCE_ID, "Aotu World")).thenReturn(Optional.empty());
        when(seasonRepository.findByOwnerUserIdAndSeriesIdAndSeasonNumber(OWNER_ID, SERIES_ID, 3))
                .thenReturn(Optional.empty());
        when(episodeRepository.findByOwnerUserIdAndSeriesIdAndSeasonNumberAndEpisodeNumber(
                OWNER_ID, SERIES_ID, 3, 1)).thenReturn(Optional.empty());
        when(videoItemRepository.findByOwnerUserIdAndFileNodeId(OWNER_ID, FILE_ID)).thenReturn(Optional.empty());

        classifier.classify(
                OWNER_ID,
                source,
                new LocalMediaScanEntry(FILE_ID, "Anime/Aotu World Ⅲ/01.mp4", "01.mp4")
        );

        ArgumentCaptor<MediaTvSeries> series = ArgumentCaptor.forClass(MediaTvSeries.class);
        ArgumentCaptor<MediaVideoItem> item = ArgumentCaptor.forClass(MediaVideoItem.class);
        verify(seriesRepository).save(series.capture());
        verify(videoItemRepository).save(item.capture());
        assertThat(series.getValue().getTitle()).isEqualTo("Aotu World");
        assertThat(item.getValue().getSeasonNumber()).isEqualTo(3);
        assertThat(item.getValue().getEpisodeNumber()).isEqualTo(1);
    }

    @Test
    void classifiesSpFileAsSeasonZeroWithoutCollidingWithRegularEpisode() {
        VideoLibrarySource source = source(MediaLibraryType.ANIME, "Anime");
        when(seriesRepository.findFirstByOwnerUserIdAndLibrarySourceIdAndTitleIgnoreCaseOrderByCreatedAtAsc(
                OWNER_ID, SOURCE_ID, "Aotu World")).thenReturn(Optional.empty());
        when(seasonRepository.findByOwnerUserIdAndSeriesIdAndSeasonNumber(OWNER_ID, SERIES_ID, 0))
                .thenReturn(Optional.empty());
        when(episodeRepository.findByOwnerUserIdAndSeriesIdAndSeasonNumberAndEpisodeNumber(
                OWNER_ID, SERIES_ID, 0, 1)).thenReturn(Optional.empty());
        when(videoItemRepository.findByOwnerUserIdAndFileNodeId(OWNER_ID, FILE_ID)).thenReturn(Optional.empty());

        classifier.classify(
                OWNER_ID,
                source,
                new LocalMediaScanEntry(FILE_ID, "Anime/Aotu World Ⅲ/SP1.mp4", "SP1.mp4")
        );

        ArgumentCaptor<MediaVideoItem> item = ArgumentCaptor.forClass(MediaVideoItem.class);
        verify(videoItemRepository).save(item.capture());
        assertThat(item.getValue().getSeasonNumber()).isZero();
        assertThat(item.getValue().getEpisodeNumber()).isEqualTo(1);
    }

    @Test
    void classifiesChineseNamedSeasonDirectoryWhenFileOnlyContainsEpisodeNumber() {
        VideoLibrarySource source = source(MediaLibraryType.ANIME, "Anime");
        when(seriesRepository.findFirstByOwnerUserIdAndLibrarySourceIdAndTitleIgnoreCaseOrderByCreatedAtAsc(
                OWNER_ID, SOURCE_ID, "葬送的芙莉莲")).thenReturn(Optional.empty());
        when(seasonRepository.findByOwnerUserIdAndSeriesIdAndSeasonNumber(OWNER_ID, SERIES_ID, 2))
                .thenReturn(Optional.empty());
        when(episodeRepository.findByOwnerUserIdAndSeriesIdAndSeasonNumberAndEpisodeNumber(
                OWNER_ID, SERIES_ID, 2, 1)).thenReturn(Optional.empty());
        when(videoItemRepository.findByOwnerUserIdAndFileNodeId(OWNER_ID, FILE_ID)).thenReturn(Optional.empty());

        classifier.classify(
                OWNER_ID,
                source,
                new LocalMediaScanEntry(FILE_ID, "Anime/葬送的芙莉莲 第二季/01.mp4", "01.mp4")
        );

        ArgumentCaptor<MediaTvSeries> series = ArgumentCaptor.forClass(MediaTvSeries.class);
        ArgumentCaptor<MediaVideoItem> item = ArgumentCaptor.forClass(MediaVideoItem.class);
        verify(seriesRepository).save(series.capture());
        verify(videoItemRepository).save(item.capture());
        assertThat(series.getValue().getTitle()).isEqualTo("葬送的芙莉莲");
        assertThat(item.getValue().getSeasonNumber()).isEqualTo(2);
    }

    @Test
    void classifiesEpisodeNumberAppendedToChineseSeriesName() {
        VideoLibrarySource source = source(MediaLibraryType.TV_SERIES, "TV Series");
        when(seriesRepository.findFirstByOwnerUserIdAndLibrarySourceIdAndTitleIgnoreCaseOrderByCreatedAtAsc(
                OWNER_ID, SOURCE_ID, "仙剑奇侠传三")).thenReturn(Optional.empty());
        when(seasonRepository.findByOwnerUserIdAndSeriesIdAndSeasonNumber(OWNER_ID, SERIES_ID, 1))
                .thenReturn(Optional.empty());
        when(episodeRepository.findByOwnerUserIdAndSeriesIdAndSeasonNumberAndEpisodeNumber(
                OWNER_ID, SERIES_ID, 1, 1)).thenReturn(Optional.empty());
        when(videoItemRepository.findByOwnerUserIdAndFileNodeId(OWNER_ID, FILE_ID)).thenReturn(Optional.empty());

        classifier.classify(
                OWNER_ID,
                source,
                new LocalMediaScanEntry(
                        FILE_ID,
                        "TV Series/仙剑奇侠传三/仙剑奇侠传三01.mp4",
                        "仙剑奇侠传三01.mp4"
                )
        );

        ArgumentCaptor<MediaTvSeries> series = ArgumentCaptor.forClass(MediaTvSeries.class);
        ArgumentCaptor<MediaVideoItem> item = ArgumentCaptor.forClass(MediaVideoItem.class);
        verify(seriesRepository).save(series.capture());
        verify(videoItemRepository).save(item.capture());
        assertThat(series.getValue().getTitle()).isEqualTo("仙剑奇侠传三");
        assertThat(item.getValue().getSeasonNumber()).isEqualTo(1);
        assertThat(item.getValue().getEpisodeNumber()).isEqualTo(1);
    }

    @Test
    void leavesUnnumberedSeriesExtrasUnmatchedInsteadOfCreatingMovie() {
        var outcome = classifier.classify(
                OWNER_ID,
                source(MediaLibraryType.TV_SERIES, "TV Series"),
                new LocalMediaScanEntry(
                        FILE_ID,
                        "TV Series/Foundation/behind-the-scenes.mkv",
                        "behind-the-scenes.mkv"
                )
        );

        assertThat(outcome).isEqualTo(LocalMediaLibraryClassifier.ClassificationOutcome.UNMATCHED);
        verify(seriesRepository, never()).save(any(MediaTvSeries.class));
        verify(movieRepository, never()).save(any());
    }

    private VideoLibrarySource source(MediaLibraryType type, String relativeRoot) {
        VideoLibrarySource source = new VideoLibrarySource();
        source.setId(SOURCE_ID);
        source.setOwnerUserId(OWNER_ID);
        source.setLibraryType(type.name());
        source.setRelativeRoot(relativeRoot);
        return source;
    }
}
