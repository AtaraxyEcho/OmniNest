package com.omninest.modules.file.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.omninest.modules.file.dto.FileMediaInfoDto;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.List;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.jupiter.api.Test;

/**
 * ffprobe 探测测试：解析用固定 JSON，进程侧用可控假进程覆盖超时、截断与临时文件清理。
 *
 * @author OmniNest
 */
class MediaProbeServiceTest {

    private static final String PROBE_JSON = """
            {
              "streams": [
                {"codec_type": "audio", "duration": "1.0"},
                {"codec_type": "video", "width": 3840, "height": 2160, "duration": "742.5"}
              ],
              "format": {"duration": "742.500"}
            }
            """;

    private final MediaProbeService service = new MediaProbeService();

    @Test
    void parsesVideoDurationAndResolution() {
        FileMediaInfoDto info = service.parseProbeJson(PROBE_JSON);
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

    @Test
    void probeCommandAsksFfprobeForJsonAndCarriesContentUrl() throws Exception {
        AtomicReference<List<String>> command = new AtomicReference<>();
        MediaProbeService probing = new MediaProbeService((args, file) -> {
            command.set(args);
            Files.writeString(file, PROBE_JSON);
            return new FakeProcess(true, false, 0);
        });

        probing.runFfprobe("http://example.test/clip.mp4");

        assertThat(command.get()).containsExactly(
                "ffprobe", "-v", "quiet", "-print_format", "json",
                "-show_format", "-show_streams", "http://example.test/clip.mp4");
    }

    @Test
    void probeReadsOutputFromRedirectedFileAndDeletesItAfterwards() throws Exception {
        AtomicReference<Path> outputFile = new AtomicReference<>();
        MediaProbeService probing = new MediaProbeService((args, file) -> {
            outputFile.set(file);
            Files.writeString(file, PROBE_JSON);
            return new FakeProcess(true, false, 0);
        });

        String json = probing.runFfprobe("http://example.test/clip.mp4");

        assertThat(json).contains("\"duration\": \"742.500\"");
        assertThat(Files.exists(outputFile.get())).isFalse();
    }

    @Test
    void probeBoundsRetainedOutputAtConfiguredLimit() throws Exception {
        byte[] output = new byte[MediaProbeService.MAX_OUTPUT_BYTES + 4096];
        Arrays.fill(output, (byte) 'a');
        MediaProbeService probing = new MediaProbeService((args, file) -> {
            Files.write(file, output);
            return new FakeProcess(true, false, 0);
        });

        String json = probing.runFfprobe("http://example.test/clip.mp4");

        assertThat(json).hasSize(MediaProbeService.MAX_OUTPUT_BYTES);
    }

    @Test
    void hungProcessIsKilledAndReportedAsTimeout() throws Exception {
        FakeProcess process = new FakeProcess(false, false, 0);
        MediaProbeService probing = new MediaProbeService((args, file) -> process);

        assertThatThrownBy(() -> probing.runFfprobe("http://example.test/clip.mp4"))
                .isInstanceOf(IOException.class)
                .hasMessageContaining("超时");
        assertThat(process.isAlive()).isFalse();
    }

    @Test
    void probeFailureWithoutInterruptKeepsThreadInterruptFlagClear() {
        MediaProbeService probing = new MediaProbeService((args, file) -> {
            throw new IOException("ffprobe 未安装");
        });

        assertThat(probing.probe("missing-binary", "http://example.test/clip.mp4").isEmpty()).isTrue();
        assertThat(Thread.interrupted()).isFalse();
    }

    @Test
    void outputTempFileIsDeletedWhenProcessCannotStart() {
        AtomicReference<Path> outputFile = new AtomicReference<>();
        MediaProbeService probing = new MediaProbeService((args, file) -> {
            outputFile.set(file);
            throw new IOException("ffprobe 未安装");
        });

        assertThatThrownBy(() -> probing.runFfprobe("http://example.test/clip.mp4"))
                .isInstanceOf(IOException.class);
        assertThat(Files.exists(outputFile.get())).isFalse();
    }

    @Test
    void interruptWhileWaitingIsPropagatedToCallerFlag() {
        MediaProbeService probing = new MediaProbeService(
                (args, file) -> new FakeProcess(true, true, 0));

        try {
            assertThat(probing.probe("interrupted", "http://example.test/clip.mp4").isEmpty()).isTrue();
            assertThat(Thread.interrupted()).isTrue();
        } finally {
            Thread.interrupted();
        }
    }

    /**
     * 可控完成状态、中断行为与退出码的测试进程。
     *
     * @author OmniNest
     */
    private static final class FakeProcess extends Process {
        private final boolean completesNormally;
        private final boolean interruptedWhileWaiting;
        private final int exitCode;
        private final ByteArrayOutputStream stdin = new ByteArrayOutputStream();
        private final InputStream stdout = new ByteArrayInputStream(new byte[0]);
        private boolean alive = true;

        private FakeProcess(boolean completesNormally, boolean interruptedWhileWaiting, int exitCode) {
            this.completesNormally = completesNormally;
            this.interruptedWhileWaiting = interruptedWhileWaiting;
            this.exitCode = exitCode;
        }

        @Override
        public OutputStream getOutputStream() {
            return stdin;
        }

        @Override
        public InputStream getInputStream() {
            return stdout;
        }

        @Override
        public InputStream getErrorStream() {
            return InputStream.nullInputStream();
        }

        @Override
        public int waitFor() {
            alive = false;
            return exitCode;
        }

        @Override
        public boolean waitFor(long timeout, TimeUnit unit) throws InterruptedException {
            if (interruptedWhileWaiting) {
                throw new InterruptedException("等待被中断");
            }
            if (completesNormally) {
                alive = false;
                return true;
            }
            return false;
        }

        @Override
        public int exitValue() {
            return exitCode;
        }

        @Override
        public void destroy() {
            alive = false;
        }

        @Override
        public Process destroyForcibly() {
            alive = false;
            return this;
        }

        @Override
        public boolean isAlive() {
            return alive;
        }
    }
}
