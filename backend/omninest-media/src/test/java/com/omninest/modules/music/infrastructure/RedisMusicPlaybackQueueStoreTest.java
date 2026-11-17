package com.omninest.modules.music.infrastructure;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.util.RedisUtil;
import com.omninest.modules.music.dto.MusicDtos.MusicPlaybackQueueDto;
import com.omninest.modules.music.dto.MusicDtos.MusicPlaybackQueueItemDto;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.Test;

/**
 * 验证 Redis 播放队列适配器和进程内降级行为。
 *
 * @author OmniNest
 */
class RedisMusicPlaybackQueueStoreTest {

    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");

    @Test
    void saveWritesRedisSnapshotWithThirtyDayTtl() {
        RedisUtil redisUtil = mock(RedisUtil.class);
        RedisMusicPlaybackQueueStore store = new RedisMusicPlaybackQueueStore(redisUtil);
        MusicPlaybackQueueDto snapshot = snapshot();

        store.save(OWNER_ID, snapshot);

        verify(redisUtil).set(
                anyString(),
                anyString(),
                eq(Duration.ofDays(30))
        );
    }

    @Test
    void redisFailureFallsBackToProcessCache() {
        RedisUtil redisUtil = mock(RedisUtil.class);
        doThrow(new IllegalStateException("redis unavailable"))
                .when(redisUtil)
                .set(anyString(), anyString(), any(Duration.class));
        when(redisUtil.get(anyString())).thenThrow(new IllegalStateException("redis unavailable"));
        RedisMusicPlaybackQueueStore store = new RedisMusicPlaybackQueueStore(redisUtil);
        MusicPlaybackQueueDto snapshot = snapshot();

        store.save(OWNER_ID, snapshot);

        assertThat(store.find(OWNER_ID)).contains(snapshot);
    }

    private MusicPlaybackQueueDto snapshot() {
        MusicPlaybackQueueItemDto item = new MusicPlaybackQueueItemDto(
                "online:netease:188888",
                "Cloud Song",
                "Cloud Artist",
                "Cloud Album",
                "https://example.com/cover.jpg",
                180,
                "mp3",
                null
        );
        return new MusicPlaybackQueueDto(
                List.of(item),
                0,
                "off",
                false,
                null,
                false,
                Instant.parse("2026-07-22T07:00:00Z")
        );
    }
}
