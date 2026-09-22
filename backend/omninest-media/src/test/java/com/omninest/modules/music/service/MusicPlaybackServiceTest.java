package com.omninest.modules.music.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.dto.FileDownloadUrlDto;
import com.omninest.modules.file.service.FileQueryService;
import com.omninest.modules.media.domain.MediaPlaybackProgress;
import com.omninest.modules.media.domain.MediaPlaybackType;
import com.omninest.modules.media.service.MediaPlaybackProgressService;
import com.omninest.modules.music.domain.MusicTrack;
import com.omninest.modules.music.dto.MusicDtos.MusicPlaybackPlanDto;
import com.omninest.modules.music.dto.MusicDtos.SaveMusicPlaybackProgressRequest;
import com.omninest.modules.music.dto.OnlineMusicDtos.PlaybackUrlResult;
import com.omninest.modules.music.repository.MusicTrackRepository;
import java.time.Instant;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

class MusicPlaybackServiceTest {
    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID TRACK_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");
    private static final UUID FILE_ID = UUID.fromString("30000000-0000-0000-0000-000000000001");

    private final MusicTrackRepository trackRepository = mock(MusicTrackRepository.class);
    private final FileQueryService fileQueryService = mock(FileQueryService.class);
    private final MusicPlatformService musicPlatformService = mock(MusicPlatformService.class);
    private final MusicPlaybackSessionService playbackSessionService = mock(MusicPlaybackSessionService.class);
    private final MediaPlaybackProgressService progressService = mock(MediaPlaybackProgressService.class);
    private final MusicPlaybackService playbackService = new MusicPlaybackService(
            trackRepository,
            fileQueryService,
            musicPlatformService,
            playbackSessionService,
            progressService
    );

    @Test
    void playbackPlanUsesOwnedTrackFileDownloadUrl() {
        MusicTrack track = new MusicTrack();
        track.setId(TRACK_ID);
        track.setOwnerUserId(OWNER_ID);
        track.setFileNodeId(FILE_ID);
        track.setTitle("Night Drive");
        track.setArtistName("Omni Band");
        track.setDurationSeconds(245);
        track.setFormat("flac");

        Instant expiresAt = Instant.parse("2026-05-21T11:00:00Z");
        when(trackRepository.findByIdAndOwnerUserId(TRACK_ID, OWNER_ID)).thenReturn(Optional.of(track));
        when(fileQueryService.createDownloadUrl(OWNER_ID, FILE_ID)).thenReturn(new FileDownloadUrlDto(
                FILE_ID,
                "night-drive.flac",
                "http://localhost:9000/night-drive.flac",
                expiresAt
        ));
        when(playbackSessionService.createLocalPlan(
                OWNER_ID,
                TRACK_ID,
                "http://localhost:9000/night-drive.flac",
                expiresAt,
                245,
                "flac"
        )).thenReturn(new MusicPlaybackPlanDto(
                TRACK_ID,
                "/api/v1/music/playback/sessions/session-1/stream?token=token",
                expiresAt,
                245,
                "flac",
                null
        ));

        var plan = playbackService.playbackPlan(OWNER_ID, TRACK_ID);

        assertThat(plan.trackId()).isEqualTo(TRACK_ID);
        assertThat(plan.url()).isEqualTo("/api/v1/music/playback/sessions/session-1/stream?token=token");
        assertThat(plan.expiresAt()).isEqualTo(expiresAt);
        assertThat(plan.durationSeconds()).isEqualTo(245);
        assertThat(plan.format()).isEqualTo("flac");
    }

    @Test
    void onlinePlaybackPlanCreatesSignedSessionPlan() {
        when(musicPlatformService.getPlaybackUrl(OWNER_ID, "netease", "song-1", "media-1", "high"))
                .thenReturn(new PlaybackUrlResult(
                        "https://music.example.com/audio.mp3",
                        "high",
                        "mp3",
                        null
                ));
        when(playbackSessionService.createOnlinePlan(
                OWNER_ID,
                "netease",
                "https://music.example.com/audio.mp3",
                null,
                "mp3"
        )).thenReturn(new MusicPlaybackPlanDto(
                null,
                "/api/v1/music/playback/sessions/session-2/stream?token=token",
                Instant.parse("2026-05-21T11:00:00Z"),
                null,
                "mp3",
                "high"
        ));

        var plan = playbackService.onlinePlaybackPlan(OWNER_ID, "netease", "song-1", "media-1", "high");

        assertThat(plan.trackId()).isNull();
        assertThat(plan.url()).isEqualTo("/api/v1/music/playback/sessions/session-2/stream?token=token");
        assertThat(plan.format()).isEqualTo("mp3");
        assertThat(plan.quality()).isEqualTo("high");
    }

    @Test
    void onlinePlaybackPlanRejectsEmptyPlatformUrl() {
        when(musicPlatformService.getPlaybackUrl(OWNER_ID, "netease", "song-1", null, "high"))
                .thenReturn(new PlaybackUrlResult(null, "high", null, "需要会员"));

        assertThatThrownBy(() -> playbackService.onlinePlaybackPlan(OWNER_ID, "netease", "song-1", null, "high"))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("需要会员");
        verify(playbackSessionService, never()).createOnlinePlan(any(), any(), any(), any(), any());
    }

    @Test
    @DisplayName("getLastPosition returns latest local media progress")
    void getLastPosition_existingProgress_returnsPosition() {
        MediaPlaybackProgress progress = progress("local:" + TRACK_ID, 120, 245);
        when(progressService.latestByPrefix(OWNER_ID, MediaPlaybackType.MUSIC, "local:"))
                .thenReturn(Optional.of(progress));

        var position = playbackService.getLastPosition(OWNER_ID);

        assertThat(position).isNotNull();
        assertThat(position.trackId()).isEqualTo(TRACK_ID);
        assertThat(position.positionSeconds()).isEqualTo(120);
    }

    @Test
    @DisplayName("getLastPosition returns null when no local progress exists")
    void getLastPosition_noLocalProgress_returnsNull() {
        when(progressService.latestByPrefix(OWNER_ID, MediaPlaybackType.MUSIC, "local:"))
                .thenReturn(Optional.empty());

        var position = playbackService.getLastPosition(OWNER_ID);

        assertThat(position).isNull();
    }

    @Test
    @DisplayName("savePosition persists local progress without creating history rows")
    void savePosition_persistsLocalProgress() {
        when(trackRepository.findByIdAndOwnerUserId(TRACK_ID, OWNER_ID))
                .thenReturn(Optional.of(new MusicTrack()));
        playbackService.savePosition(OWNER_ID, TRACK_ID, 90);

        verify(progressService).save(
                OWNER_ID,
                MediaPlaybackType.MUSIC,
                "local:" + TRACK_ID,
                90,
                0,
                false
        );
    }

    @Test
    void saveProgressSupportsOnlinePlayableKey() {
        Instant clientUpdatedAt = Instant.parse("2026-07-10T04:00:00Z");
        MediaPlaybackProgress stored = progress("online:netease:song-1", 75, 180);
        when(progressService.save(
                OWNER_ID,
                MediaPlaybackType.MUSIC,
                "online:netease:song-1",
                75,
                180,
                false,
                clientUpdatedAt,
                "desktop-test"
        )).thenReturn(stored);

        var result = playbackService.saveProgress(
                OWNER_ID,
                new SaveMusicPlaybackProgressRequest(
                        "online:netease:song-1",
                        75,
                        180,
                        false,
                        clientUpdatedAt,
                        "desktop-test"
                )
        );

        assertThat(result.playableKey()).isEqualTo("online:netease:song-1");
        assertThat(result.positionSeconds()).isEqualTo(75);
    }

    @Test
    void saveProgressRejectsUnsupportedOnlinePlatform() {
        SaveMusicPlaybackProgressRequest request =
                new SaveMusicPlaybackProgressRequest(
                        "online:unknown:song-1",
                        10,
                        180,
                        false,
                        Instant.parse("2026-07-10T04:00:00Z"),
                        "desktop-test"
                );

        assertThatThrownBy(() -> playbackService.saveProgress(OWNER_ID, request))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("不支持的音乐平台");
    }

    @Test
    void saveProgressRejectsLocalTrackOwnedByAnotherUser() {
        when(trackRepository.findByIdAndOwnerUserId(TRACK_ID, OWNER_ID))
                .thenReturn(Optional.empty());

        assertThatThrownBy(() -> playbackService.saveProgress(
                OWNER_ID,
                new SaveMusicPlaybackProgressRequest(
                        "local:" + TRACK_ID,
                        10,
                        180,
                        false,
                        Instant.parse("2026-07-10T04:00:00Z"),
                        "desktop-test"
                )
        )).isInstanceOf(BusinessException.class)
                .hasMessageContaining("音乐资源不存在");
    }

    private MediaPlaybackProgress progress(String mediaKey, long position, long duration) {
        MediaPlaybackProgress progress = new MediaPlaybackProgress();
        progress.setOwnerUserId(OWNER_ID);
        progress.setMediaType(MediaPlaybackType.MUSIC.value());
        progress.setMediaKey(mediaKey);
        progress.setPositionSeconds(position);
        progress.setDurationSeconds(duration);
        progress.setUpdatedAt(Instant.parse("2026-07-10T04:00:00Z"));
        return progress;
    }
}
