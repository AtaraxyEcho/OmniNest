package com.omninest.modules.music.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.modules.music.dto.MusicDtos.MusicPlaybackQueueDto;
import com.omninest.modules.music.dto.MusicDtos.MusicPlaybackQueueItemDto;
import com.omninest.modules.music.dto.MusicDtos.MusicQueueSourceDto;
import com.omninest.modules.music.dto.MusicDtos.SaveMusicPlaybackQueueRequest;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import java.util.stream.IntStream;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

/**
 * 验证播放队列校验和规范化规则。
 *
 * @author OmniNest
 */
class MusicPlaybackQueueServiceTest {

    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");

    private final MusicPlaybackQueueStore queueStore = mock(MusicPlaybackQueueStore.class);
    private final MusicPlaybackQueueService service = new MusicPlaybackQueueService(queueStore);

    @Test
    void savePreservesStableOnlineDescriptorWithoutPlaybackUrl() {
        MusicPlaybackQueueItemDto item = onlineItem();

        MusicPlaybackQueueDto saved = service.save(
                OWNER_ID,
                new SaveMusicPlaybackQueueRequest(List.of(item), 0, "all", true, null, null)
        );

        assertThat(saved.items()).containsExactly(item);
        assertThat(saved.currentIndex()).isZero();
        assertThat(saved.repeatMode()).isEqualTo("all");
        assertThat(saved.shuffleEnabled()).isTrue();
        verify(queueStore).save(OWNER_ID, saved);
    }

    @Test
    void unsupportedPlayableKeysAreSoftFilteredOnSave() {
        MusicPlaybackQueueItemDto invalid = new MusicPlaybackQueueItemDto(
                "online:unknown:song-1",
                "Song",
                "Artist",
                "Album",
                "",
                180,
                "mp3",
                null
        );
        MusicPlaybackQueueItemDto valid = onlineItem();

        MusicPlaybackQueueDto saved = service.save(
                OWNER_ID,
                new SaveMusicPlaybackQueueRequest(List.of(invalid, valid), 1, "off", false, null, null)
        );

        assertThat(saved.items()).containsExactly(valid);
        assertThat(saved.currentIndex()).isZero();
    }

    @Test
    void storedQueueIsLimitedToOneHundredItems() {
        List<MusicPlaybackQueueItemDto> items = IntStream.range(0, 120)
                .mapToObj(index -> new MusicPlaybackQueueItemDto(
                        "online:netease:song-" + index,
                        "Song " + index,
                        "Artist",
                        "Album",
                        "",
                        180,
                        "mp3",
                        null
                ))
                .toList();
        MusicPlaybackQueueDto stored = new MusicPlaybackQueueDto(
                items,
                119,
                "all",
                false,
                null,
                false,
                Instant.now()
        );
        when(queueStore.find(OWNER_ID)).thenReturn(Optional.of(stored));

        MusicPlaybackQueueDto loaded = service.load(OWNER_ID);

        assertThat(loaded.items()).hasSize(100);
        assertThat(loaded.currentIndex()).isEqualTo(99);
    }

    @Test
    void missingQueueReturnsEmptySnapshot() {
        when(queueStore.find(OWNER_ID)).thenReturn(Optional.empty());

        MusicPlaybackQueueDto loaded = service.load(OWNER_ID);

        assertThat(loaded.items()).isEmpty();
        assertThat(loaded.currentIndex()).isEqualTo(-1);
    }

    @Test
    void saveNormalizesQueueSourceAndTruncation() {
        MusicPlaybackQueueItemDto item = onlineItem();

        MusicPlaybackQueueDto saved = service.save(
                OWNER_ID,
                new SaveMusicPlaybackQueueRequest(
                        List.of(item),
                        0,
                        "off",
                        false,
                        new MusicQueueSourceDto("playlist", "playlist-1", "Road Trip", List.of("local")),
                        true
                )
        );

        assertThat(saved.source()).isNotNull();
        assertThat(saved.source().kind()).isEqualTo("playlist");
        assertThat(saved.source().platforms()).isNull();
        assertThat(saved.truncated()).isTrue();

        MusicPlaybackQueueDto invalidKind = service.save(
                OWNER_ID,
                new SaveMusicPlaybackQueueRequest(
                        List.of(item),
                        0,
                        "off",
                        false,
                        new MusicQueueSourceDto("bogus", null, null, null),
                        null
                )
        );
        assertThat(invalidKind.source()).isNull();
        assertThat(invalidKind.truncated()).isFalse();
    }

    @Test
    void loadNormalizesLibrarySourcePlatforms() {
        MusicPlaybackQueueItemDto item = onlineItem();
        MusicPlaybackQueueDto stored = new MusicPlaybackQueueDto(
                List.of(item),
                0,
                "off",
                false,
                new MusicQueueSourceDto("library", null, null, List.of("local")),
                true,
                Instant.now()
        );
        when(queueStore.find(OWNER_ID)).thenReturn(Optional.of(stored));

        MusicPlaybackQueueDto loaded = service.load(OWNER_ID);

        assertThat(loaded.source()).isNotNull();
        assertThat(loaded.source().platforms()).containsExactly("local");
        assertThat(loaded.truncated()).isTrue();
    }

    @Test
    void removePlatformTracksDropsOnlyThatPlatformAndClearsCurrentItem() {
        MusicPlaybackQueueItemDto local = localItem(1);
        MusicPlaybackQueueDto stored = new MusicPlaybackQueueDto(
                List.of(local, onlineItem(), onlineItem()),
                1,
                "all",
                false,
                new MusicQueueSourceDto("library", null, null, List.of("local", "netease")),
                false,
                Instant.now()
        );
        when(queueStore.find(OWNER_ID)).thenReturn(Optional.of(stored));

        int removed = service.removePlatformTracks(OWNER_ID, "netease");

        assertThat(removed).isEqualTo(2);
        ArgumentCaptor<MusicPlaybackQueueDto> captor =
                ArgumentCaptor.forClass(MusicPlaybackQueueDto.class);
        verify(queueStore).save(eq(OWNER_ID), captor.capture());
        MusicPlaybackQueueDto persisted = captor.getValue();
        assertThat(persisted.items())
                .extracting(MusicPlaybackQueueItemDto::playableKey)
                .containsExactly(local.playableKey());
        // 当前项被剔除：置为无当前曲，避免继续用已删除的凭据拉流。
        assertThat(persisted.currentIndex()).isEqualTo(-1);
        // 库来源的 platforms 同步摘除已断开平台，否则来源标签仍指向它。
        assertThat(persisted.source()).isNotNull();
        assertThat(persisted.source().platforms()).containsExactly("local");
    }

    @Test
    void removePlatformTracksShiftsCurrentIndexWhenEarlierItemsRemoved() {
        MusicPlaybackQueueDto stored = new MusicPlaybackQueueDto(
                List.of(onlineItem(), localItem(1), localItem(2)),
                1,
                "off",
                false,
                null,
                false,
                Instant.now()
        );
        when(queueStore.find(OWNER_ID)).thenReturn(Optional.of(stored));

        assertThat(service.removePlatformTracks(OWNER_ID, "netease")).isEqualTo(1);

        ArgumentCaptor<MusicPlaybackQueueDto> captor =
                ArgumentCaptor.forClass(MusicPlaybackQueueDto.class);
        verify(queueStore).save(eq(OWNER_ID), captor.capture());
        assertThat(captor.getValue().currentIndex()).isZero();
    }

    @Test
    void removePlatformTracksSkipsWriteWhenNothingMatches() {
        MusicPlaybackQueueDto stored = new MusicPlaybackQueueDto(
                List.of(localItem(0)),
                0,
                "off",
                false,
                null,
                false,
                Instant.now()
        );
        when(queueStore.find(OWNER_ID)).thenReturn(Optional.of(stored));

        assertThat(service.removePlatformTracks(OWNER_ID, "netease")).isZero();
        verify(queueStore, never()).save(any(), any());
    }

    private MusicPlaybackQueueItemDto onlineItem() {
        return new MusicPlaybackQueueItemDto(
                "online:netease:188888",
                "Cloud Song",
                "Cloud Artist",
                "Cloud Album",
                "https://example.com/cover.jpg",
                180,
                "mp3",
                null
        );
    }

    private MusicPlaybackQueueItemDto localItem(int index) {
        return new MusicPlaybackQueueItemDto(
                "local:10000000-0000-0000-0000-" + String.format("%012d", index),
                "Local Song " + index,
                "Local Artist",
                "Local Album",
                "",
                200,
                "flac",
                null
        );
    }
}
