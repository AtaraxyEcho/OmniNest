package com.omninest.modules.music.service;

import static org.assertj.core.api.Assertions.assertThat;

import com.omninest.modules.music.dto.MusicDtos.MusicPlaybackPlanDto;
import java.net.URI;
import java.time.Instant;
import java.util.HashMap;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;

/**
 * 音乐播放会话服务测试。
 *
 * @author OmniNest
 */
class MusicPlaybackSessionServiceTest {
    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID TRACK_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");

    private final MusicPlaybackTokenService tokenService =
            new MusicPlaybackTokenService(new TestPayloadAuthenticator());
    private final InMemorySessionStore sessionStore = new InMemorySessionStore();
    private final MusicPlaybackSessionService sessionService =
            new MusicPlaybackSessionService(tokenService, sessionStore);

    @Test
    void createLocalPlanReturnsSignedApiUrlAndResolvableSession() {
        Instant sourceExpiresAt = Instant.now().plusSeconds(60);

        MusicPlaybackPlanDto plan = sessionService.createLocalPlan(
                OWNER_ID,
                TRACK_ID,
                "http://localhost:9000/audio.flac",
                sourceExpiresAt,
                245,
                "flac"
        );
        ParsedPlaybackUrl parsedUrl = parsePlaybackUrl(plan.url());

        assertThat(plan.trackId()).isEqualTo(TRACK_ID);
        assertThat(plan.url()).startsWith("/api/v1/music/playback/sessions/");
        assertThat(plan.url()).contains("/stream?token=");
        assertThat(plan.url()).doesNotContain("audio.flac");
        assertThat(plan.expiresAt()).isEqualTo(sourceExpiresAt);

        var session = sessionService.resolve(parsedUrl.sessionId(), parsedUrl.token());

        assertThat(session).isPresent();
        assertThat(session.get().ownerUserId()).isEqualTo(OWNER_ID);
        assertThat(session.get().trackId()).isEqualTo(TRACK_ID);
        assertThat(session.get().sourceType()).isEqualTo(MusicPlaybackSourceType.LOCAL);
        assertThat(session.get().sourceUrl()).isEqualTo("http://localhost:9000/audio.flac");
        assertThat(session.get().durationSeconds()).isEqualTo(245);
        assertThat(session.get().format()).isEqualTo("flac");
    }

    @Test
    void resolveRejectsTamperedToken() {
        MusicPlaybackPlanDto plan = sessionService.createOnlinePlan(
                OWNER_ID,
                "netease",
                "https://music.example.com/audio.mp3",
                180,
                "mp3"
        );
        ParsedPlaybackUrl parsedUrl = parsePlaybackUrl(plan.url());

        var session = sessionService.resolve(parsedUrl.sessionId(), parsedUrl.token() + "x");

        assertThat(session).isEmpty();
    }

    @Test
    void warmCacheStillVerifiesTokenEveryRequest() {
        MusicPlaybackPlanDto plan = sessionService.createOnlinePlan(
                OWNER_ID,
                "netease",
                "https://music.example.com/audio.mp3",
                180,
                "mp3"
        );
        ParsedPlaybackUrl parsedUrl = parsePlaybackUrl(plan.url());

        assertThat(sessionService.resolve(parsedUrl.sessionId(), parsedUrl.token())).isPresent();
        assertThat(sessionService.resolve(parsedUrl.sessionId(), parsedUrl.token() + "x")).isEmpty();
        assertThat(sessionService.resolve(parsedUrl.sessionId(), parsedUrl.token())).isPresent();
    }

    @Test
    void warmCacheAvoidsRepeatedStoreLookups() {
        MusicPlaybackPlanDto plan = sessionService.createLocalPlan(
                OWNER_ID,
                TRACK_ID,
                "http://localhost:9000/audio.flac",
                Instant.now().plusSeconds(600),
                245,
                "flac"
        );
        ParsedPlaybackUrl parsedUrl = parsePlaybackUrl(plan.url());
        int findsBefore = sessionStore.findCount;

        sessionService.resolve(parsedUrl.sessionId(), parsedUrl.token());
        sessionService.resolve(parsedUrl.sessionId(), parsedUrl.token());

        assertThat(sessionStore.findCount - findsBefore).isEqualTo(1);
    }

    @Test
    void createOnlinePlanHidesSourceUrlAndUsesOnlineSourceType() {
        MusicPlaybackPlanDto plan = sessionService.createOnlinePlan(
                OWNER_ID,
                "netease",
                "https://music.example.com/audio.mp3",
                180,
                "mp3"
        );
        ParsedPlaybackUrl parsedUrl = parsePlaybackUrl(plan.url());

        var session = sessionService.resolve(parsedUrl.sessionId(), parsedUrl.token());

        assertThat(plan.trackId()).isNull();
        assertThat(plan.url()).doesNotContain("music.example.com");
        assertThat(session).isPresent();
        assertThat(session.get().sourceType()).isEqualTo(MusicPlaybackSourceType.ONLINE);
        assertThat(session.get().sourcePlatform()).isEqualTo("netease");
        assertThat(session.get().sourceUrl()).isEqualTo("https://music.example.com/audio.mp3");
    }

    private ParsedPlaybackUrl parsePlaybackUrl(String url) {
        URI uri = URI.create("http://localhost" + url);
        String[] segments = uri.getPath().split("/");
        String sessionId = segments[segments.length - 2];
        String token = uri.getQuery().replace("token=", "");
        return new ParsedPlaybackUrl(sessionId, token);
    }

    private record ParsedPlaybackUrl(String sessionId, String token) {
    }

    /**
     * 测试使用的内存播放会话存储。
     *
     * @author OmniNest
     */
    private static final class InMemorySessionStore implements MusicPlaybackSessionStore {
        private final Map<String, MusicPlaybackSession> sessions = new HashMap<>();
        private int findCount;

        @Override
        public void save(MusicPlaybackSession session) {
            sessions.put(session.sessionId(), session);
        }

        @Override
        public Optional<MusicPlaybackSession> find(String sessionId) {
            findCount++;
            return Optional.ofNullable(sessions.get(sessionId));
        }

        @Override
        public void delete(String sessionId) {
            sessions.remove(sessionId);
        }
    }
}
