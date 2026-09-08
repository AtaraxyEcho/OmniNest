package com.omninest.modules.media.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.omninest.modules.media.domain.MediaPlaybackProgress;
import com.omninest.modules.media.domain.MediaPlaybackType;
import com.omninest.modules.media.repository.MediaPlaybackProgressRepository;
import java.time.Instant;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.context.ApplicationEventPublisher;

/**
 * 统一媒体播放进度服务测试。
 *
 * @author OmniNest
 */
class MediaPlaybackProgressServiceTest {
    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");

    private final MediaPlaybackProgressRepository repository = mock(MediaPlaybackProgressRepository.class);
    private final MediaSyncEventService syncEventService = mock(MediaSyncEventService.class);
    private final ApplicationEventPublisher applicationEventPublisher = mock(ApplicationEventPublisher.class);
    private final MediaPlaybackProgressService service = new MediaPlaybackProgressService(
            repository,
            syncEventService,
            applicationEventPublisher
    );

    @Test
    void saveCreatesTypedProgressAndClampsPosition() {
        MediaPlaybackProgress stored = progress(
                "online:netease:song-1",
                180,
                180,
                Instant.parse("2026-08-10T00:00:00Z"),
                "legacy"
        );
        when(repository.upsertIfNewer(
                any(UUID.class),
                eq(OWNER_ID),
                eq(MediaPlaybackType.MUSIC.value()),
                eq("online:netease:song-1"),
                eq(180L),
                eq(180L),
                eq(false),
                any(Instant.class),
                eq("legacy"),
                any(Instant.class)
        )).thenReturn(Optional.of(stored));

        MediaPlaybackProgress progress = service.save(
                OWNER_ID,
                MediaPlaybackType.MUSIC,
                "online:netease:song-1",
                240,
                180,
                false
        );

        assertThat(progress.getOwnerUserId()).isEqualTo(OWNER_ID);
        assertThat(progress.getMediaType()).isEqualTo("music");
        assertThat(progress.getMediaKey()).isEqualTo("online:netease:song-1");
        assertThat(progress.getPositionSeconds()).isEqualTo(180);
        verify(repository).upsertIfNewer(
                any(UUID.class),
                eq(OWNER_ID),
                eq(MediaPlaybackType.MUSIC.value()),
                eq("online:netease:song-1"),
                eq(180L),
                eq(180L),
                eq(false),
                any(Instant.class),
                eq("legacy"),
                any(Instant.class)
        );
    }

    @Test
    void saveReturnsCurrentProgressWhenClientEventIsStale() {
        Instant currentClientTime = Instant.parse("2026-08-10T01:00:00Z");
        Instant staleClientTime = Instant.parse("2026-08-10T00:59:00Z");
        MediaPlaybackProgress current = progress(
                "movie:item-1",
                600,
                3600,
                currentClientTime,
                "desktop-a"
        );
        when(repository.upsertIfNewer(
                any(UUID.class),
                eq(OWNER_ID),
                eq(MediaPlaybackType.VIDEO.value()),
                eq("movie:item-1"),
                eq(120L),
                eq(3600L),
                eq(false),
                eq(staleClientTime),
                eq("mobile-b"),
                any(Instant.class)
        )).thenReturn(Optional.empty());
        when(repository.findByOwnerUserIdAndMediaTypeAndMediaKey(
                OWNER_ID,
                MediaPlaybackType.VIDEO.value(),
                "movie:item-1"
        )).thenReturn(Optional.of(current));

        MediaPlaybackProgress result = service.save(
                OWNER_ID,
                MediaPlaybackType.VIDEO,
                "movie:item-1",
                120,
                3600,
                false,
                staleClientTime,
                "mobile-b"
        );

        assertThat(result).isSameAs(current);
        assertThat(result.getPositionSeconds()).isEqualTo(600);
        verifyNoInteractions(syncEventService);
    }

    private MediaPlaybackProgress progress(
            String mediaKey,
            long positionSeconds,
            long durationSeconds,
            Instant clientUpdatedAt,
            String deviceId
    ) {
        MediaPlaybackProgress progress = new MediaPlaybackProgress();
        progress.setId(UUID.randomUUID());
        progress.setOwnerUserId(OWNER_ID);
        progress.setMediaType(mediaKey.startsWith("movie:") ? "video" : "music");
        progress.setMediaKey(mediaKey);
        progress.setPositionSeconds(positionSeconds);
        progress.setDurationSeconds(durationSeconds);
        progress.setUpdatedAt(clientUpdatedAt);
        progress.setClientUpdatedAt(clientUpdatedAt);
        progress.setDeviceId(deviceId);
        return progress;
    }
}
