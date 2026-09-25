package com.omninest.modules.video.service;
import com.omninest.modules.media.config.MediaProcessingLimitsProperties;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.modules.file.dto.FileContentStream;
import com.omninest.modules.file.dto.FileDownloadUrlDto;
import com.omninest.modules.file.service.FileQueryService;
import com.omninest.modules.media.domain.MediaPlaybackProgress;
import com.omninest.modules.media.domain.MediaPlaybackType;
import com.omninest.modules.media.service.MediaPlaybackProgressService;
import com.omninest.modules.video.domain.MediaSubtitleTrack;
import com.omninest.modules.video.domain.MediaVideoItem;
import com.omninest.modules.video.repository.MediaMovieRepository;
import com.omninest.modules.video.repository.MediaSubtitleTrackRepository;
import com.omninest.modules.video.repository.MediaTvEpisodeRepository;
import com.omninest.modules.video.repository.MediaVideoItemRepository;
import com.omninest.modules.video.repository.MediaWatchHistoryRepository;
import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionStatus;
import org.springframework.transaction.support.SimpleTransactionStatus;

/**
 * 影视播放服务单元测试。
 *
 * @author OmniNest
 */
class MoviePlaybackServiceTest {
    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID MOVIE_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");
    private static final UUID FILE_ID = UUID.fromString("30000000-0000-0000-0000-000000000001");
    private static final UUID SUBTITLE_ID = UUID.fromString("40000000-0000-0000-0000-000000000001");

    private final MediaVideoItemRepository videoItemRepository = mock(MediaVideoItemRepository.class);
    private final MediaMovieRepository movieRepository = mock(MediaMovieRepository.class);
    private final MediaTvEpisodeRepository episodeRepository = mock(MediaTvEpisodeRepository.class);
    private final MediaPlaybackProgressService progressService =
            mock(MediaPlaybackProgressService.class);
    private final MediaSubtitleTrackRepository subtitleTrackRepository =
            mock(MediaSubtitleTrackRepository.class);
    private final FileQueryService fileQueryService = mock(FileQueryService.class);
    private final MediaWatchHistoryRepository historyRepository =
            mock(MediaWatchHistoryRepository.class);
    private final MovieTaskService movieTaskService = mock(MovieTaskService.class);
    private final MediaRuntimeConfigService mediaRuntimeConfigService = mock(MediaRuntimeConfigService.class);
    private final PlatformTransactionManager transactionManager = mock(PlatformTransactionManager.class);
    private final VideoTranscodeService videoTranscodeService = mock(VideoTranscodeService.class);
    private final MediaContentAccessService mediaContentAccessService = mock(MediaContentAccessService.class);
    private final MediaPlaybackTokenService mediaPlaybackTokenService = mock(MediaPlaybackTokenService.class);

    private final MoviePlaybackService playbackService = new MoviePlaybackService(
            videoItemRepository, movieRepository, episodeRepository, progressService,
            subtitleTrackRepository, fileQueryService, historyRepository,
            movieTaskService, new MediaProcessingLimitsProperties(), mediaRuntimeConfigService, transactionManager, videoTranscodeService,
            mediaContentAccessService, mediaPlaybackTokenService);

    @Test
    void writeSubtitleContentStreamsOwnedFileThroughFileService() throws Exception {
        MediaSubtitleTrack track = new MediaSubtitleTrack();
        track.setId(SUBTITLE_ID);
        track.setOwnerUserId(OWNER_ID);
        track.setFileNodeId(FILE_ID);
        when(subtitleTrackRepository.findById(SUBTITLE_ID)).thenReturn(Optional.of(track));
        MediaVideoItem item = new MediaVideoItem();
        item.setOwnerUserId(OWNER_ID);
        item.setId(MOVIE_ID);
        track.setVideoItemId(MOVIE_ID);
        when(mediaContentAccessService.requireReadableVideo(OWNER_ID, MOVIE_ID)).thenReturn(item);
        when(fileQueryService.openOwnedFileContent(OWNER_ID, FILE_ID)).thenReturn(new FileContentStream(
                new ByteArrayInputStream("WEBVTT\n\n00:00.000 --> 00:01.000\n字幕".getBytes(StandardCharsets.UTF_8)),
                "subtitle.vtt",
                45,
                "text/vtt"
        ));

        java.io.ByteArrayOutputStream out = new java.io.ByteArrayOutputStream();
        playbackService.writeSubtitleContent(OWNER_ID, SUBTITLE_ID, out);

        String content = out.toString(StandardCharsets.UTF_8);
        assertThat(content).contains("WEBVTT").contains("字幕");
    }

    @Test
    void playbackPlanUsesFileDownloadUrlAndSavedProgress() {
        // 让 TransactionTemplate 正常执行回调
        TransactionStatus txStatus = new SimpleTransactionStatus();
        when(transactionManager.getTransaction(any())).thenReturn(txStatus);

        MediaVideoItem movie = new MediaVideoItem();
        movie.setId(MOVIE_ID);
        movie.setOwnerUserId(OWNER_ID);
        movie.setFileNodeId(FILE_ID);
        movie.setContainerFormat("mp4");
        movie.setVideoCodec("h264");
        movie.setAudioCodec("aac");
        movie.setMetadataStatus("MATCHED");

        MediaPlaybackProgress progress = new MediaPlaybackProgress();
        progress.setPositionSeconds(600);
        progress.setDurationSeconds(7200);

        when(mediaContentAccessService.requireReadableVideo(OWNER_ID, MOVIE_ID)).thenReturn(movie);
        when(mediaPlaybackTokenService.issue(OWNER_ID, MOVIE_ID)).thenReturn(
                new MediaPlaybackTokenService.IssuedMediaToken(
                        "media-token",
                        Instant.parse("2026-05-21T11:00:00Z")
                )
        );
        when(progressService.find(OWNER_ID, MediaPlaybackType.VIDEO, MOVIE_ID.toString()))
                .thenReturn(Optional.of(progress));
        when(subtitleTrackRepository.findByOwnerUserIdAndVideoItemIdOrderBySortOrderAsc(OWNER_ID, MOVIE_ID))
                .thenReturn(List.of());
        when(fileQueryService.createDownloadUrl(OWNER_ID, FILE_ID)).thenReturn(new FileDownloadUrlDto(
                FILE_ID,
                "inception.mp4",
                "http://localhost:9000/video.mp4",
                Instant.parse("2026-05-21T11:00:00Z")
        ));

        var plan = playbackService.playbackPlan(OWNER_ID, MOVIE_ID);

        assertThat(plan.mode()).isEqualTo("DIRECT_PLAY");
        assertThat(plan.url()).isEqualTo("http://localhost:9000/video.mp4");
        assertThat(plan.positionSeconds()).isEqualTo(600);
        assertThat(plan.container()).isEqualTo("mp4");
    }

    @Test
    void matroskaAv1OpusPlaysDirectAsWebmFamily() {
        MediaVideoItem movie = new MediaVideoItem();
        movie.setId(MOVIE_ID);
        movie.setOwnerUserId(OWNER_ID);
        movie.setFileNodeId(FILE_ID);
        movie.setContainerFormat("MATROSKA,WEBM");
        movie.setVideoCodec("AV1");
        movie.setAudioCodec("OPUS");
        movie.setMetadataStatus("MATCHED");

        when(mediaContentAccessService.requireReadableVideo(OWNER_ID, MOVIE_ID)).thenReturn(movie);
        when(mediaPlaybackTokenService.issue(OWNER_ID, MOVIE_ID)).thenReturn(
                new MediaPlaybackTokenService.IssuedMediaToken(
                        "media-token",
                        Instant.parse("2026-05-21T11:00:00Z")
                )
        );
        when(progressService.find(OWNER_ID, MediaPlaybackType.VIDEO, MOVIE_ID.toString()))
                .thenReturn(Optional.empty());
        when(subtitleTrackRepository.findByOwnerUserIdAndVideoItemIdOrderBySortOrderAsc(OWNER_ID, MOVIE_ID))
                .thenReturn(List.of());
        when(fileQueryService.createDownloadUrl(OWNER_ID, FILE_ID)).thenReturn(new FileDownloadUrlDto(
                FILE_ID,
                "night.webm",
                "http://localhost:9000/night.webm",
                Instant.parse("2026-05-21T11:00:00Z")
        ));

        var plan = playbackService.playbackPlan(OWNER_ID, MOVIE_ID);

        assertThat(plan.mode())
                .as("matroska 容器中 av1+opus 属 WebM 家族，应直接播放")
                .isEqualTo("DIRECT_PLAY");
    }

    @Test
    void doesNotAutoTriggerTranscodeWhenDisabled() {
        TransactionStatus txStatus = new SimpleTransactionStatus();
        when(transactionManager.getTransaction(any())).thenReturn(txStatus);

        MediaVideoItem movie = new MediaVideoItem();
        movie.setId(MOVIE_ID);
        movie.setOwnerUserId(OWNER_ID);
        movie.setFileNodeId(FILE_ID);
        movie.setContainerFormat("mp4");
        movie.setVideoCodec("h264");
        movie.setAudioCodec("aac");
        movie.setMetadataStatus("MATCHED");

        when(mediaContentAccessService.requireReadableVideo(OWNER_ID, MOVIE_ID)).thenReturn(movie);
        when(mediaPlaybackTokenService.issue(OWNER_ID, MOVIE_ID)).thenReturn(
                new MediaPlaybackTokenService.IssuedMediaToken(
                        "media-token",
                        Instant.parse("2026-05-21T11:00:00Z")
                )
        );
        when(progressService.find(OWNER_ID, MediaPlaybackType.VIDEO, MOVIE_ID.toString()))
                .thenReturn(Optional.empty());
        when(subtitleTrackRepository.findByOwnerUserIdAndVideoItemIdOrderBySortOrderAsc(OWNER_ID, MOVIE_ID))
                .thenReturn(List.of());
        when(fileQueryService.createDownloadUrl(OWNER_ID, FILE_ID)).thenReturn(new FileDownloadUrlDto(
                FILE_ID,
                "movie.mp4",
                "http://localhost:9000/movie.mp4",
                Instant.parse("2026-05-21T11:00:00Z")
        ));
        when(mediaRuntimeConfigService.transcodeEnabled()).thenReturn(false);

        playbackService.playbackPlan(OWNER_ID, MOVIE_ID);

        verify(movieTaskService, never()).createTranscodeTask(any(), any(), anyBoolean());
    }
}
