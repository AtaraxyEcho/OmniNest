package com.omninest.modules.music.service;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Instant;
import org.junit.jupiter.api.Test;

/**
 * 音乐播放令牌服务测试。
 *
 * @author OmniNest
 */
class MusicPlaybackTokenServiceTest {
    private final MusicPlaybackTokenService tokenService =
            new MusicPlaybackTokenService(new TestPayloadAuthenticator());

    @Test
    void verifyAcceptsSignedTokenBeforeExpiration() {
        Instant expiresAt = Instant.parse("2026-05-21T11:00:00Z");
        String token = tokenService.sign("session-1", expiresAt);

        boolean valid = tokenService.verify(
                token,
                "session-1",
                expiresAt,
                Instant.parse("2026-05-21T10:59:59Z")
        );

        assertThat(valid).isTrue();
    }

    @Test
    void verifyRejectsTamperedSessionId() {
        Instant expiresAt = Instant.parse("2026-05-21T11:00:00Z");
        String token = tokenService.sign("session-1", expiresAt);

        boolean valid = tokenService.verify(
                token,
                "session-2",
                expiresAt,
                Instant.parse("2026-05-21T10:59:59Z")
        );

        assertThat(valid).isFalse();
    }

    @Test
    void verifyRejectsExpiredToken() {
        Instant expiresAt = Instant.parse("2026-05-21T11:00:00Z");
        String token = tokenService.sign("session-1", expiresAt);

        boolean valid = tokenService.verify(
                token,
                "session-1",
                expiresAt,
                Instant.parse("2026-05-21T11:00:01Z")
        );

        assertThat(valid).isFalse();
    }
}
