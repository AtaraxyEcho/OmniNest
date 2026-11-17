package com.omninest.modules.music.infrastructure;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.omninest.common.error.BusinessException;
import com.omninest.common.util.RedisUtil;
import com.omninest.modules.music.service.MusicPlaybackSession;
import com.omninest.modules.music.service.MusicPlaybackSourceType;
import java.time.Duration;
import java.time.Instant;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
import org.springframework.core.env.Environment;
import org.springframework.core.env.Profiles;

/**
 * Redis 播放会话存储降级测试。
 *
 * @author OmniNest
 */
class RedisMusicPlaybackSessionStoreTest {

    @Test
    void saveFallsBackToProcessCacheWhenRedisIsUnavailable() {
        RedisUtil redisUtil = Mockito.mock(RedisUtil.class);
        Mockito.doThrow(new IllegalStateException("redis unavailable"))
                .when(redisUtil)
                .set(Mockito.anyString(), Mockito.anyString(), Mockito.any(Duration.class));
        Environment environment = Mockito.mock(Environment.class);
        RedisMusicPlaybackSessionStore store = new RedisMusicPlaybackSessionStore(
                redisUtil,
                environment
        );
        MusicPlaybackSession session = new MusicPlaybackSession(
                "session-1",
                UUID.fromString("10000000-0000-0000-0000-000000000001"),
                null,
                MusicPlaybackSourceType.ONLINE,
                "netease",
                "https://music.example.com/audio.mp3",
                Instant.now().plusSeconds(60),
                180,
                "mp3"
        );

        store.save(session);

        assertThat(store.find(session.sessionId())).contains(session);
    }

    @Test
    void saveFailsClosedInProductionWhenRedisIsUnavailable() {
        RedisUtil redisUtil = Mockito.mock(RedisUtil.class);
        Mockito.doThrow(new IllegalStateException("redis unavailable"))
                .when(redisUtil)
                .set(Mockito.anyString(), Mockito.anyString(), Mockito.any(Duration.class));
        Environment environment = Mockito.mock(Environment.class);
        Mockito.when(environment.acceptsProfiles(Mockito.any(Profiles.class))).thenReturn(true);
        RedisMusicPlaybackSessionStore store = new RedisMusicPlaybackSessionStore(
                redisUtil,
                environment
        );
        MusicPlaybackSession session = new MusicPlaybackSession(
                "session-prod",
                UUID.fromString("10000000-0000-0000-0000-000000000001"),
                null,
                MusicPlaybackSourceType.ONLINE,
                "netease",
                "https://music.example.com/audio.mp3",
                Instant.now().plusSeconds(60),
                180,
                "mp3"
        );

        assertThatThrownBy(() -> store.save(session))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("写入音乐播放会话失败");
    }

    @Test
    void readsLegacyOnlineSessionWithoutSourcePlatform() {
        RedisUtil redisUtil = Mockito.mock(RedisUtil.class);
        String payload = """
                {
                  "sessionId":"legacy-session",
                  "ownerUserId":"10000000-0000-0000-0000-000000000001",
                  "trackId":null,
                  "sourceType":"ONLINE",
                  "sourceUrl":"https://music.example.com/audio.mp3",
                  "expiresAt":"2026-08-03T18:00:00Z",
                  "durationSeconds":180,
                  "format":"mp3"
                }
                """;
        Mockito.when(redisUtil.get("omninest:music:playback:session:legacy-session"))
                .thenReturn(payload);
        Environment environment = Mockito.mock(Environment.class);
        RedisMusicPlaybackSessionStore store = new RedisMusicPlaybackSessionStore(
                redisUtil,
                environment
        );

        Optional<MusicPlaybackSession> session = store.find("legacy-session");

        assertThat(session).isPresent();
        assertThat(session.orElseThrow().sourcePlatform()).isNull();
    }
}
