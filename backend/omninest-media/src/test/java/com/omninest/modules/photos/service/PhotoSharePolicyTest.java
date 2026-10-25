package com.omninest.modules.photos.service;

import static org.assertj.core.api.Assertions.assertThat;

import com.omninest.modules.photos.dto.PhotoDtos.PhotoItemDto;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;

class PhotoSharePolicyTest {

    private static final UUID PHOTO_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID FILE_NODE_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");
    private static final UUID COVER_FILE_ID = UUID.fromString("30000000-0000-0000-0000-000000000001");

    private PhotoItemDto dto() {
        return dto(COVER_FILE_ID);
    }

    private PhotoItemDto dto(UUID coverFileId) {
        return new PhotoItemDto(
                PHOTO_ID,
                FILE_NODE_ID,
                "t",
                null,
                100,
                50,
                null,
                null,
                null,
                null,
                null,
                null,
                null,
                null,
                null,
                null,
                null,
                null,
                1.5,
                2.5,
                Map.of("city", "Beijing"),
                "JPEG",
                10L,
                "https://example/cover",
                "https://example/source",
                "READY",
                false,
                null,
                List.of(),
                null,
                null,
                "READY",
                "https://example/motion.mp4",
                true,
                coverFileId
        );
    }

    @Test
    void applySharePolicy_keepsAllWhenBothEnabled() {
        PhotoItemDto source = dto();
        PhotoItemDto result = PhotoAlbumService.applySharePolicy(source, true, true);
        assertThat(result).isSameAs(source);
    }

    @Test
    void applySharePolicy_stripsGpsWhenLocationDisabled() {
        PhotoItemDto result = PhotoAlbumService.applySharePolicy(dto(), false, true);
        assertThat(result.gpsLatitude()).isNull();
        assertThat(result.gpsLongitude()).isNull();
        assertThat(result.gpsLocation()).isNull();
        assertThat(result.sourceUrl()).isEqualTo("https://example/source");
    }

    @Test
    void applySharePolicy_stripsSourceWhenOriginalQualityDisabled() {
        PhotoItemDto result = PhotoAlbumService.applySharePolicy(dto(), true, false);
        assertThat(result.sourceUrl()).isNull();
        assertThat(result.motionVideoUrl()).isNull();
        assertThat(result.coverUrl()).isEqualTo("https://example/cover");
        assertThat(result.gpsLatitude()).isEqualTo(1.5);
    }

    @Test
    void applySharePolicy_hidesCoverWhenItPointsToOriginal() {
        PhotoItemDto result = PhotoAlbumService.applySharePolicy(dto(FILE_NODE_ID), true, false);

        assertThat(result.coverUrl()).isNull();
        assertThat(result.sourceUrl()).isNull();
    }
}
