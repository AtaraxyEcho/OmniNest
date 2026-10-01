package com.omninest.modules.file.service;

import static org.assertj.core.api.Assertions.assertThat;

import com.omninest.modules.file.dto.FileMediaInfoDto;
import org.junit.jupiter.api.Test;

/**
 * ffprobe 输出解析测试（探测进程本身不在 CI 内执行）。
 *
 * @author OmniNest
 */
class MediaProbeServiceTest {

    private final MediaProbeService service = new MediaProbeService();

    @Test
    void parsesVideoDurationAndResolution() {
        String json = """
                {
                  "streams": [
                    {"codec_type": "audio", "duration": "1.0"},
                    {"codec_type": "video", "width": 3840, "height": 2160, "duration": "742.5"}
                  ],
                  "format": {"duration": "742.500"}
                }
                """;
        FileMediaInfoDto info = service.parseProbeJson(json);
        assertThat(info.durationSeconds()).isEqualTo(742.500);
        assertThat(info.width()).isEqualTo(3840);
        assertThat(info.height()).isEqualTo(2160);
        assertThat(info.isEmpty()).isFalse();
    }

    @Test
    void fallsBackToStreamDurationAndImageDimensions() {
        String json = """
                {
                  "streams": [
                    {"codec_type": "video", "width": 4032, "height": 3024}
                  ]
                }
                """;
        FileMediaInfoDto info = service.parseProbeJson(json);
        assertThat(info.durationSeconds()).isNull();
        assertThat(info.width()).isEqualTo(4032);
        assertThat(info.height()).isEqualTo(3024);
    }

    @Test
    void malformedOrEmptyOutputYieldsEmptyResult() {
        assertThat(service.parseProbeJson("").isEmpty()).isTrue();
        assertThat(service.parseProbeJson("not json").isEmpty()).isTrue();
        assertThat(service.parseProbeJson("{\"streams\": []}").isEmpty()).isTrue();
    }
}
