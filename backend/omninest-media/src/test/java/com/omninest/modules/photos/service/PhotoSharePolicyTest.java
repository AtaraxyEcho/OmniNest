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
                Map.of("city", "Beijing", "gps_latitude", 1.5, "Address", "北京市"),
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
    void applySharePolicy_stripsGpsAndOriginalLinksWhenLocationDisabled() {
        PhotoItemDto result = PhotoAlbumService.applySharePolicy(dto(), false, true);
        assertThat(result.gpsLatitude()).isNull();
        assertThat(result.gpsLongitude()).isNull();
        assertThat(result.gpsLocation()).isNull();
        // 原图与实况视频内嵌 EXIF 坐标，关闭位置时连同封面原图一起撤下。
        assertThat(result.sourceUrl()).isNull();
        assertThat(result.motionVideoUrl()).isNull();
        // 独立派生封面不含原图元数据，关闭位置时仍然可用。
        assertThat(result.coverUrl()).isEqualTo("https://example/cover");
    }

    @Test
    void applySharePolicy_stripsLocationKeysFromProviderMetadataWhenLocationDisabled() {
        PhotoItemDto result = PhotoAlbumService.applySharePolicy(dto(), false, false);

        assertThat(result.providerMetadata())
                .containsEntry("city", "Beijing")
                .doesNotContainKeys("gps_latitude", "Address");
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
    void applySharePolicy_keepsOriginalCoverWhenLocationVisible() {
        // 包含位置时封面原图不构成位置泄露；置空会让没有派生缩略图的照片破图。
        PhotoItemDto result = PhotoAlbumService.applySharePolicy(dto(FILE_NODE_ID), true, false);

        assertThat(result.coverUrl()).isEqualTo("https://example/cover");
        assertThat(result.sourceUrl()).isNull();
    }

    @Test
    void applySharePolicy_hidesOriginalCoverWhenLocationHidden() {
        PhotoItemDto result = PhotoAlbumService.applySharePolicy(dto(FILE_NODE_ID), false, false);

        assertThat(result.coverUrl()).isNull();
    }
}
