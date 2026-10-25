package com.omninest.modules.video.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.omninest.common.error.BusinessException;
import java.util.UUID;
import org.junit.jupiter.api.Test;

class MediaPlaybackTokenServiceTest {

    private final MediaPlaybackTokenService service =
            new MediaPlaybackTokenService("test-media-playback-secret-0123456789");

    @Test
    void videoTokenIsScopedToOneVideoItem() {
        UUID userId = UUID.randomUUID();
        UUID videoItemId = UUID.randomUUID();
        var token = service.issue(userId, videoItemId);

        assertThat(service.requireGrant(token.token(), videoItemId).requesterUserId()).isEqualTo(userId);
        assertThatThrownBy(() -> service.requireGrant(token.token(), UUID.randomUUID()))
                .isInstanceOf(BusinessException.class);
    }

    @Test
    void seriesTokenCannotBeUsedAsVideoToken() {
        UUID userId = UUID.randomUUID();
        UUID seriesId = UUID.randomUUID();
        var token = service.issueSeries(userId, seriesId);

        assertThat(service.requireSeriesGrant(token.token(), seriesId).requesterUserId()).isEqualTo(userId);
        assertThatThrownBy(() -> service.requireGrant(token.token(), seriesId))
                .isInstanceOf(BusinessException.class);
    }

}
