package com.omninest.modules.user.dto;

import static org.assertj.core.api.Assertions.assertThat;

import com.omninest.modules.user.domain.AuthActiveSession;
import java.time.Instant;
import java.util.UUID;
import org.junit.jupiter.api.Test;

class MeSessionDtoTest {

    @Test
    void from_marksCurrentOnlyForMatchingSessionId() {
        UUID currentSessionId = UUID.randomUUID();
        UUID otherSessionId = UUID.randomUUID();

        MeSessionDto current = MeSessionDto.from(session(currentSessionId), currentSessionId);
        MeSessionDto other = MeSessionDto.from(session(otherSessionId), currentSessionId);

        assertThat(current.current()).isTrue();
        assertThat(other.current()).isFalse();
    }

    @Test
    void from_toleratesMissingCurrentSessionId() {
        UUID sessionId = UUID.randomUUID();
        MeSessionDto dto = MeSessionDto.from(session(sessionId), null);
        assertThat(dto.current()).isFalse();
    }

    private AuthActiveSession session(UUID sessionId) {
        Instant now = Instant.now();
        return new AuthActiveSession(
                sessionId,
                UUID.randomUUID(),
                "web",
                "device-1",
                "Windows 11 · Chrome",
                "192.168.1.108",
                now,
                now.plusSeconds(3600),
                now,
                null,
                null,
                now
        );
    }
}
