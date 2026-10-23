package com.omninest.modules.video.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;

import java.util.List;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * ffmpeg 运行位置与协议白名单测试。
 *
 * @author OmniNest
 */
class VideoFfmpegRuntimeTest {

    private final VideoFfmpegRuntime runtime = new VideoFfmpegRuntime(mock(VideoProcessExecutor.class));

    @Test
    @DisplayName("HTTP 输入只放行网络协议，本地路径只放行文件协议")
    void protocolWhitelistDependsOnInputKind() {
        assertThat(runtime.protocolWhitelist("http://minio:9000/video.mp4"))
                .isEqualTo("http,https,tcp,tls");
        assertThat(runtime.protocolWhitelist("/mnt/local-media/movie.mkv"))
                .isEqualTo("file,crypto,data");
    }

    @Test
    @DisplayName("本地命令在 -i 之前声明协议白名单")
    void localCommandPutsWhitelistBeforeInput() {
        List<String> command = runtime.localCommand(
                "http://minio:9000/video.mp4", List.of("-c:v", "copy", "out.mp4"));

        assertThat(command).startsWith("ffmpeg", "-y", "-protocol_whitelist");
        assertThat(command.indexOf("-protocol_whitelist")).isLessThan(command.indexOf("-i"));
        assertThat(command).containsSubsequence("-i", "http://minio:9000/video.mp4", "-c:v", "copy");
    }

    @Test
    @DisplayName("docker 命令带 PID 文件包装，便于终止容器内孤儿进程")
    void dockerStreamCommandWrapsWithPidFile() {
        String marker = runtime.newMarker();
        List<String> command = runtime.dockerStreamCommand(marker, List.of("-y", "-i", "http://x"));
        String script = command.get(command.indexOf("-c") + 1);

        assertThat(command).startsWith("docker", "exec", VideoFfmpegRuntime.DOCKER_CONTAINER);
        assertThat(script).contains("/tmp/omninest-stream-" + marker + ".pid");
        assertThat(runtime.dockerKillCommand(marker)).hasSize(6);
    }
}
