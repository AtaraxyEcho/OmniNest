package com.omninest.modules.music.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.sun.net.httpserver.HttpServer;
import com.omninest.common.security.RequestPrincipal;
import com.omninest.modules.file.dto.FileContentRange;
import com.omninest.modules.file.dto.FileContentStream;
import com.omninest.modules.music.domain.MusicTrack;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.servlet.mvc.method.annotation.StreamingResponseBody;

/**
 * 音乐播放流网关单元测试。
 *
 * @author OmniNest
 */
class MusicStreamGatewayServiceTest {

    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final RequestPrincipal REQUESTER = RequestPrincipal.credential(() -> OWNER_ID);
    private static final String SESSION_ID = "session-1";
    private static final String TOKEN = "token-1";
    private static final UUID TRACK_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");
    private static final UUID FILE_NODE_ID = UUID.fromString("30000000-0000-0000-0000-000000000001");

    private final MusicPlaybackSessionService sessionService = mock(MusicPlaybackSessionService.class);
    private final MusicOnlineSourceUrlPolicy sourceUrlPolicy = mock(MusicOnlineSourceUrlPolicy.class);

    private final com.omninest.modules.music.repository.MusicTrackRepository trackRepository =
            mock(com.omninest.modules.music.repository.MusicTrackRepository.class);
    private final com.omninest.modules.file.service.FilePlaybackContentService filePlaybackContentService =
            mock(com.omninest.modules.file.service.FilePlaybackContentService.class);
    private final com.omninest.modules.file.service.FileMetadataQueryService fileMetadataQueryService =
            mock(com.omninest.modules.file.service.FileMetadataQueryService.class);

    private final MusicStreamGatewayService service = new MusicStreamGatewayService(
            sessionService,
            sourceUrlPolicy,
            trackRepository,
            filePlaybackContentService,
            fileMetadataQueryService
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

    @Test
    void localSessionServesPartialContentForRangeRequest() throws Exception {
        stubLocalTrack();
        byte[] slice = new byte[] {7, 8, 9};
        when(filePlaybackContentService.openFileContent(REQUESTER, FILE_NODE_ID))
                .thenAnswer(invocation -> new FileContentStream(
                        new ByteArrayInputStream(new byte[10]), "track.flac", 10L, "audio/flac"));
        when(filePlaybackContentService.openFileRange(REQUESTER, FILE_NODE_ID, 2L, 3L))
                .thenAnswer(invocation -> Optional.of(
                        new FileContentRange(new ByteArrayInputStream(slice), 10L)));

        ResponseEntity<StreamingResponseBody> response =
                service.stream(SESSION_ID, TOKEN, "bytes=2-4", false);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.PARTIAL_CONTENT);
        assertThat(response.getHeaders().getFirst("Content-Range")).isEqualTo("bytes 2-4/10");
        assertThat(response.getHeaders().getFirst("Content-Length")).isEqualTo("3");
        assertThat(response.getHeaders().getFirst("Accept-Ranges")).isEqualTo("bytes");
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        response.getBody().writeTo(out);
        assertThat(out.toByteArray()).containsExactly(slice);
    }

    @Test
    void localSessionServesFullContentWithoutRange() throws Exception {
        stubLocalTrack();
        byte[] payload = new byte[] {1, 2, 3, 4};
        when(filePlaybackContentService.openFileContent(REQUESTER, FILE_NODE_ID))
                .thenAnswer(invocation -> new FileContentStream(
                        new ByteArrayInputStream(payload), "track.flac", payload.length, "audio/flac"));

        ResponseEntity<StreamingResponseBody> response =
                service.stream(SESSION_ID, TOKEN, null, false);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getHeaders().getFirst("Content-Length")).isEqualTo("4");
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        response.getBody().writeTo(out);
        assertThat(out.toByteArray()).containsExactly(payload);
    }

    @Test
    void localSessionRejectsUnsatisfiableRange() {
        stubLocalTrack();
        when(filePlaybackContentService.openFileContent(REQUESTER, FILE_NODE_ID))
                .thenAnswer(invocation -> new FileContentStream(
                        new ByteArrayInputStream(new byte[10]), "track.flac", 10L, "audio/flac"));

        ResponseEntity<StreamingResponseBody> response =
                service.stream(SESSION_ID, TOKEN, "bytes=99-", false);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.REQUESTED_RANGE_NOT_SATISFIABLE);
        assertThat(response.getHeaders().getFirst("Content-Range")).isEqualTo("bytes */10");
    }

    @Test
    void localSessionHeadClosesContentStreamWithoutBody() throws Exception {
        stubLocalTrack();
        final boolean[] contentClosed = {false};
        when(filePlaybackContentService.openFileContent(REQUESTER, FILE_NODE_ID))
                .thenAnswer(invocation -> new FileContentStream(
                        new ByteArrayInputStream(new byte[10]) {
                            @Override
                            public void close() {
                                contentClosed[0] = true;
                            }
                        },
                        "track.flac",
                        10L,
                        "audio/flac"));

        ResponseEntity<StreamingResponseBody> response =
                service.stream(SESSION_ID, TOKEN, null, true);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isNull();
        assertThat(contentClosed[0]).isTrue();
    }

    private void stubLocalTrack() {
        MusicTrack track = new MusicTrack();
        track.setId(TRACK_ID);
        track.setOwnerUserId(OWNER_ID);
        track.setFileNodeId(FILE_NODE_ID);
        track.setTitle("Night Drive");
        track.setFormat("flac");
        track.setDurationSeconds(180);
        when(trackRepository.findById(TRACK_ID)).thenReturn(Optional.of(track));
        // 文件大小来自元数据：本地流不再为探测大小额外打开一次对象存储。
        when(fileMetadataQueryService.findAllByIds(java.util.List.of(FILE_NODE_ID)))
                .thenReturn(java.util.List.of(new com.omninest.modules.file.dto.FileDescriptor(
                        FILE_NODE_ID,
                        OWNER_ID,
                        null,
                        "FILE",
                        "track.flac",
                        "/track.flac",
                        "audio/flac",
                        10L,
                        null,
                        "UPLOAD",
                        false,
                        false,
                        com.omninest.modules.file.domain.SpaceType.PERSONAL,
                        OWNER_ID,
                        null,
                        null)));
        MusicPlaybackSession session = new MusicPlaybackSession(
                SESSION_ID,
                OWNER_ID,
                TRACK_ID,
                MusicPlaybackSourceType.LOCAL,
                null,
                null,
                Instant.now().plusSeconds(600),
                180,
                "flac"
        );
        when(sessionService.resolve(anyString(), anyString())).thenReturn(Optional.of(session));
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
