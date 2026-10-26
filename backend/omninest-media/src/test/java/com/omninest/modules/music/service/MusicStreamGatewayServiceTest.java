package com.omninest.modules.music.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.sun.net.httpserver.HttpServer;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.http.ResponseEntity;
import org.springframework.web.servlet.mvc.method.annotation.StreamingResponseBody;

/**
 * 音乐播放流网关单元测试。
 *
 * @author OmniNest
 */
class MusicStreamGatewayServiceTest {

    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final String SESSION_ID = "session-1";
    private static final String TOKEN = "token-1";

    private final MusicPlaybackSessionService sessionService = mock(MusicPlaybackSessionService.class);
    private final MusicOnlineSourceUrlPolicy sourceUrlPolicy = mock(MusicOnlineSourceUrlPolicy.class);

    private final com.omninest.modules.music.repository.MusicTrackRepository trackRepository =
            mock(com.omninest.modules.music.repository.MusicTrackRepository.class);
    private final com.omninest.modules.file.service.FilePlaybackContentService filePlaybackContentService =
            mock(com.omninest.modules.file.service.FilePlaybackContentService.class);

    private final MusicStreamGatewayService service = new MusicStreamGatewayService(
            sessionService,
            sourceUrlPolicy,
            trackRepository,
            filePlaybackContentService
    );

    @Test
    void streamCopiesUpstreamBody() throws Exception {
        HttpServer server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        byte[] payload = new byte[] {1, 2, 3, 4};
        server.createContext("/audio.mp3", exchange -> {
            exchange.getResponseHeaders().add("Content-Type", "audio/mpeg");
            exchange.sendResponseHeaders(200, payload.length);
            try (OutputStream out = exchange.getResponseBody()) {
                out.write(payload);
            }
        });
        server.start();
        try {
            stubLocalSession("http://127.0.0.1:" + server.getAddress().getPort() + "/audio.mp3");
            ResponseEntity<StreamingResponseBody> response = service.stream(SESSION_ID, TOKEN, null, false);

            assertThat(response.getStatusCode().is2xxSuccessful()).isTrue();
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            response.getBody().writeTo(out);
            assertThat(out.toByteArray()).containsExactly(payload);
        } finally {
            server.stop(0);
        }
    }

    @Test
    void streamBodyDoesNotPropagateClientDisconnect() throws Exception {
        HttpServer server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        byte[] payload = "audio".getBytes(StandardCharsets.UTF_8);
        server.createContext("/audio.mp3", exchange -> {
            exchange.sendResponseHeaders(200, payload.length);
            try (OutputStream out = exchange.getResponseBody()) {
                out.write(payload);
            }
        });
        server.start();
        try {
            stubLocalSession("http://127.0.0.1:" + server.getAddress().getPort() + "/audio.mp3");
            ResponseEntity<StreamingResponseBody> response = service.stream(SESSION_ID, TOKEN, null, false);
            assertThat(response.getBody()).isNotNull();

            OutputStream brokenPipe = new OutputStream() {
                @Override
                public void write(int b) throws IOException {
                    throw new IOException("Broken pipe", new InterruptedException("interrupted"));
                }
            };

            assertThatCode(() -> response.getBody().writeTo(brokenPipe))
                    .doesNotThrowAnyException();
        } finally {
            server.stop(0);
        }
    }

    private void stubLocalSession(String sourceUrl) {
        // 本地曲库已改为服务端直读 File 内容；这里保留上游 HTTP 转发用例，
        // 因此以在线来源构造会话（同样走 sendWithRedirects 分支）。
        MusicPlaybackSession session = new MusicPlaybackSession(
                SESSION_ID,
                OWNER_ID,
                null,
                MusicPlaybackSourceType.ONLINE,
                "netease",
                sourceUrl,
                Instant.now().plusSeconds(600),
                180,
                "mp3"
        );
        when(sessionService.resolve(anyString(), anyString())).thenReturn(Optional.of(session));
    }
}
