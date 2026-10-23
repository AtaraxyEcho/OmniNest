package com.omninest.modules.video.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.omninest.common.config.ProcessingTempProperties;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.UUID;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.Assumptions;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

/**
 * 本地 ffmpeg 转码的实机回归：验证命令构造、协议白名单与临时输出落盘。
 *
 * @author OmniNest
 */
class VideoTranscodeLocalIntegrationTest {

    @TempDir
    Path tempDir;

    @Test
    @DisplayName("本机 ffmpeg 可按本地输入完成转码并写出临时文件")
    void transcodesLocalInputWithHostFfmpeg() throws Exception {
        Assumptions.assumeTrue(ffmpegAvailable(), "当前环境没有 ffmpeg，跳过实机转码");
        Path input = tempDir.resolve("input.mp4");
        ProcessBuilder generate = new ProcessBuilder(
                "ffmpeg", "-y",
                "-f", "lavfi", "-i", "testsrc=duration=1:size=320x240:rate=15",
                "-f", "lavfi", "-i", "sine=frequency=440:duration=1",
                "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", "-shortest",
                input.toAbsolutePath().toString()
        ).redirectErrorStream(true).redirectOutput(tempDir.resolve("generate.log").toFile());
        Process generated = generate.start();
        Assumptions.assumeTrue(
                generated.waitFor(60, TimeUnit.SECONDS) && generated.exitValue() == 0,
                "生成测试视频失败");

        VideoProcessExecutor executor = new VideoProcessExecutor();
        VideoFfmpegRuntime runtime = new VideoFfmpegRuntime(executor);
        Assumptions.assumeTrue(runtime.mode() == VideoFfmpegRuntime.Mode.LOCAL,
                "当前环境未探测到本地 ffmpeg");

        ProcessingTempProperties properties = new ProcessingTempProperties();
        properties.setRoot(tempDir.resolve("processing").toString());
        VideoSourceInputResolver resolver = mock(VideoSourceInputResolver.class);
        UUID ownerId = UUID.randomUUID();
        UUID fileNodeId = UUID.randomUUID();
        when(resolver.resolveLocalInput(ownerId, fileNodeId)).thenReturn(input.toAbsolutePath().toString());

        VideoTranscodeService service = new VideoTranscodeService(properties, resolver, executor, runtime);
        Path output = service.transcodeToWebOptimized(ownerId, fileNodeId, UUID.randomUUID(), "h264");

        assertThat(Files.size(output)).isPositive();
        Files.deleteIfExists(output);
    }

    private boolean ffmpegAvailable() {
        try {
            Process process = new ProcessBuilder("ffmpeg", "-version")
                    .redirectErrorStream(true)
                    .redirectOutput(ProcessBuilder.Redirect.DISCARD)
                    .start();
            return process.waitFor(10, TimeUnit.SECONDS) && process.exitValue() == 0;
        } catch (Exception exception) {
            return false;
        }
    }
}
