package com.omninest.modules.video.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import org.junit.jupiter.api.Test;

/**
 * 直播输入容器白名单测试。
 *
 * @author OmniNest
 */
class VideoLiveInputFormatsTest {

    @Test
    void mapsScannedFfprobeNamesToForcedDemuxers() {
        assertThat(VideoLiveInputFormats.requireDemuxer("mov,mp4,m4a,3gp,3g2,mj2")).isEqualTo("mov");
        assertThat(VideoLiveInputFormats.requireDemuxer("MATROSKA,WEBM")).isEqualTo("matroska");
        assertThat(VideoLiveInputFormats.requireDemuxer("mpegts")).isEqualTo("mpegts");
    }

    @Test
    void rejectsPlaylistContainersEvenWhenCombinedWithKnownNames() {
        assertRejected("hls");
        assertRejected("dash");
        assertRejected("mov,hls");
        assertRejected("concat");
    }

    @Test
    void rejectsBlankAndUnknownContainers() {
        assertRejected(null);
        assertRejected(" ");
        assertRejected("totally-unknown-container");
    }

    private void assertRejected(String containerFormat) {
        assertThatThrownBy(() -> VideoLiveInputFormats.requireDemuxer(containerFormat))
                .isInstanceOfSatisfying(BusinessException.class,
                        exception -> assertThat(exception.errorCode())
                                .isEqualTo(ErrorCode.MEDIA_FORMAT_UNSUPPORTED));
    }
}
