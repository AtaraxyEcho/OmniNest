package com.omninest.modules.video.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;

import com.omninest.modules.video.config.VideoStreamProperties;
import com.omninest.modules.video.repository.MediaVideoItemRepository;
import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;
import java.io.IOException;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Assumptions;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * 直播链路内嵌远程引用的实机回归。
 *
 * <p>用实际 ffmpeg 验证：强制 demuxer 后，伪装成普通视频文件的播放列表不会再被探测成 HLS，
 * 因此播放列表里内嵌的分片地址不会被请求。对照组不指定 demuxer，必须能看到分片请求，
 * 否则测试对回归不敏感。</p>
 *
 * @author OmniNest
 */
class VideoLiveEgressGuardIntegrationTest {

    private HttpServer server;
    private String playlistUrl;
    private final AtomicInteger segmentRequests = new AtomicInteger();

    @BeforeEach
    void setUp() throws IOException {
        server = HttpServer.create(new InetSocketAddress(InetAddress.getLoopbackAddress(), 0), 0);
        int port = server.getAddress().getPort();
        server.createContext("/movie.m3u8", exchange -> respond(
                exchange,
                "#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:1\n"
                        + "#EXT-X-MEDIA-SEQUENCE:0\n#EXTINF:1.0,\n"
                        + "http://127.0.0.1:" + port + "/segment.ts\n#EXT-X-ENDLIST\n"
        ));
        server.createContext("/segment.ts", exchange -> {
            segmentRequests.incrementAndGet();
            respond(exchange, new byte[]{0x47, 0x40, 0x00, 0x10});
        });
        server.start();
        playlistUrl = "http://127.0.0.1:" + port + "/movie.m3u8";
    }

    @AfterEach
    void tearDown() {
        server.stop(0);
    }

    @Test
    @DisplayName("强制 demuxer 后播放列表内嵌分片不会被请求")
    void forcedDemuxerDoesNotFetchPlaylistSegment() throws Exception {
        Assumptions.assumeTrue(ffmpegAvailable(), "当前环境没有 ffmpeg，跳过实机回归");

        VideoStreamService service = new VideoStreamService(
                mock(MediaVideoItemRepository.class),
                mock(VideoSourceInputResolver.class),
                mock(MediaContentAccessService.class),
                new VideoStreamProperties(),
                new VideoFfmpegRuntime(new VideoProcessExecutor())
        );
        VideoStreamService.StreamCommand command = service.buildStreamCommand(
                service.buildTranscodeArgs("mov", playlistUrl, 0L),
                List.of(playlistUrl)
        );

        int exitCode = run(command.command());

        assertThat(exitCode).isNotZero();
        assertThat(segmentRequests.get()).isZero();
    }

    @Test
    @DisplayName("对照组：自动探测会把播放列表当作 HLS 并请求分片")
    void autoDetectionFetchesPlaylistSegment() throws Exception {
        Assumptions.assumeTrue(ffmpegAvailable(), "当前环境没有 ffmpeg，跳过实机对照");

        run(List.of(
                "ffmpeg", "-y",
                "-protocol_whitelist", "http,https,tcp,tls",
                "-i", playlistUrl,
                "-t", "1",
                "-f", "null", "-"
        ));

        assertThat(segmentRequests.get()).isGreaterThan(0);
    }

    private int run(List<String> command) throws Exception {
        Process process = new ProcessBuilder(command)
                .redirectOutput(ProcessBuilder.Redirect.DISCARD)
                .redirectError(ProcessBuilder.Redirect.DISCARD)
                .start();
        if (!process.waitFor(30, TimeUnit.SECONDS)) {
            process.destroyForcibly();
            throw new AssertionError("ffmpeg 未在 30 秒内退出");
        }
        return process.exitValue();
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

    private void respond(HttpExchange exchange, String body) throws IOException {
        respond(exchange, body.getBytes(StandardCharsets.UTF_8));
    }

    private void respond(HttpExchange exchange, byte[] body) throws IOException {
        exchange.sendResponseHeaders(200, body.length);
        exchange.getResponseBody().write(body);
        exchange.close();
    }
}
