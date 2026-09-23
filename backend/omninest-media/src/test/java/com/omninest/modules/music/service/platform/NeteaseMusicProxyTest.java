package com.omninest.modules.music.service.platform;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.argThat;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.music.dto.OnlineMusicDtos.PlatformUserInfo;
import com.omninest.modules.music.service.MusicPlatformCredentialService;
import com.omninest.modules.music.service.MusicRuntimeConfigService;
import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpHandler;
import com.sun.net.httpserver.HttpServer;
import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.jupiter.api.Test;

/**
 * 网易云音乐响应映射测试。
 *
 * @author OmniNest
 */
class NeteaseMusicProxyTest {
    private final NeteaseMusicProxy proxy = new NeteaseMusicProxy(
            mock(MusicRuntimeConfigService.class),
            mock(MusicPlatformCredentialService.class)
    );

    @Test
    void parsePlaylistMapsAccountPlaylistMetadata() {
        JSONObject payload = JSONObject.parseObject("""
                {
                  "id": 123456,
                  "name": "Daily Mix",
                  "description": "Favorites",
                  "coverImgUrl": "https://example.com/cover.jpg",
                  "trackCount": 42,
                  "subscribed": true,
                  "creator": {"userId": 99, "nickname": "Music User"}
                }
                """);

        var playlist = proxy.parsePlaylist(payload);

        assertThat(playlist.playlistId()).isEqualTo("123456");
        assertThat(playlist.name()).isEqualTo("Daily Mix");
        assertThat(playlist.trackCount()).isEqualTo(42);
        assertThat(playlist.subscribed()).isTrue();
        assertThat(playlist.ownerName()).isEqualTo("Music User");
        assertThat(playlist.thumbUrl()).isEqualTo("https://example.com/cover.jpg?paramSize=300x300");
    }

    @Test
    void thumbnailUrlOnlyRewritesPlainImageAddresses() {
        assertThat(NeteaseMusicProxy.thumbnailUrl("https://p3.music.126.net/a.jpg"))
                .isEqualTo("https://p3.music.126.net/a.jpg?paramSize=300x300");
        assertThat(NeteaseMusicProxy.thumbnailUrl("https://p3.music.126.net/a.jpg?id=7"))
                .isEqualTo("https://p3.music.126.net/a.jpg?id=7&paramSize=300x300");
        assertThat(NeteaseMusicProxy.thumbnailUrl("https://p3.music.126.net/a.jpg?paramSize=200x200"))
                .isEqualTo("https://p3.music.126.net/a.jpg?paramSize=200x200");
        assertThat(NeteaseMusicProxy.thumbnailUrl("")).isEmpty();
        assertThat(NeteaseMusicProxy.thumbnailUrl(null)).isNull();
    }

    @Test
    void parseSongsMapsPlaylistTrackShape() {
        JSONArray songs = JSONArray.parseArray("""
                [{
                  "id": 1001,
                  "name": "Night Drive",
                  "dt": 245000,
                  "ar": [{"name": "Omni Band"}],
                  "al": {"id": 2001, "name": "City Lights", "picUrl": "https://example.com/a.jpg"}
                }]
                """);

        var tracks = proxy.parseSongs(songs);

        assertThat(tracks).hasSize(1);
        assertThat(tracks.getFirst().songId()).isEqualTo("1001");
        assertThat(tracks.getFirst().artistName()).isEqualTo("Omni Band");
        assertThat(tracks.getFirst().durationSeconds()).isEqualTo(245);
        assertThat(tracks.getFirst().coverUrl()).isEqualTo("https://example.com/a.jpg");
        assertThat(tracks.getFirst().thumbUrl()).isEqualTo("https://example.com/a.jpg?paramSize=300x300");
    }

    @Test
    void parseDailyRecommendedTracksKeepsOrderAndRemovesDuplicates() {
        JSONObject payload = JSONObject.parseObject("""
                {
                  "code": 200,
                  "data": {
                    "dailySongs": [
                      {
                        "id": 1001,
                        "name": "First Song",
                        "dt": 180000,
                        "ar": [{"name": "First Artist"}],
                        "al": {"name": "First Album", "picUrl": "https://example.com/first.jpg"}
                      },
                      {
                        "id": 1001,
                        "name": "First Song",
                        "dt": 180000,
                        "ar": [{"name": "First Artist"}],
                        "al": {"name": "First Album", "picUrl": "https://example.com/first.jpg"}
                      },
                      {
                        "id": 1002,
                        "name": "Second Song",
                        "dt": 210000,
                        "ar": [{"name": "Second Artist"}],
                        "al": {"name": "Second Album", "picUrl": "https://example.com/second.jpg"}
                      }
                    ]
                  }
                }
                """);

        var tracks = proxy.parseDailyRecommendedTracks(payload);

        assertThat(tracks).extracting(track -> track.songId()).containsExactly("1001", "1002");
    }

    @Test
    void dailyRecommendationClearsCredentialOnlyAfterConfirmedExpiration() throws IOException {
        MusicRuntimeConfigService configService = mock(MusicRuntimeConfigService.class);
        MusicPlatformCredentialService credentialService = mock(MusicPlatformCredentialService.class);
        HttpServer server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/", exchange -> {
            String path = exchange.getRequestURI().getPath();
            String response = "/recommend/songs".equals(path)
                    ? "{\"code\":301}"
                    : "{\"data\":{\"account\":null,\"profile\":null}}";
            writeJson(exchange, response);
        });
        server.start();
        try {
            UUID ownerUserId = UUID.randomUUID();
            when(configService.neteaseBaseUrl()).thenReturn(
                    "http://127.0.0.1:" + server.getAddress().getPort()
            );
            when(credentialService.find(ownerUserId, MusicPlatform.NETEASE)).thenReturn(
                    Optional.of(credential("expired-user"))
            );
            NeteaseMusicProxy localProxy = new NeteaseMusicProxy(configService, credentialService);

            assertThatThrownBy(() -> localProxy.dailyRecommendedTracks(ownerUserId))
                    .isInstanceOfSatisfying(BusinessException.class, exception ->
                            assertThat(exception.errorCode()).isEqualTo(ErrorCode.MUSIC_PLATFORM_AUTH_EXPIRED)
                    );
            verify(credentialService).clear(ownerUserId, MusicPlatform.NETEASE);
        } finally {
            server.stop(0);
        }
    }

    @Test
    void dailyRecommendationKeepsCredentialWhenLoginStatusRemainsActive() throws IOException {
        MusicRuntimeConfigService configService = mock(MusicRuntimeConfigService.class);
        MusicPlatformCredentialService credentialService = mock(MusicPlatformCredentialService.class);
        HttpServer server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/", exchange -> {
            String path = exchange.getRequestURI().getPath();
            String response = "/recommend/songs".equals(path)
                    ? "{\"code\":301}"
                    : "{\"data\":{\"account\":{\"id\":40004},\"profile\":null}}";
            writeJson(exchange, response);
        });
        server.start();
        try {
            UUID ownerUserId = UUID.randomUUID();
            when(configService.neteaseBaseUrl()).thenReturn(
                    "http://127.0.0.1:" + server.getAddress().getPort()
            );
            when(credentialService.find(ownerUserId, MusicPlatform.NETEASE)).thenReturn(
                    Optional.of(credential("active-user"))
            );
            NeteaseMusicProxy localProxy = new NeteaseMusicProxy(configService, credentialService);

            assertThatThrownBy(() -> localProxy.dailyRecommendedTracks(ownerUserId))
                    .isInstanceOfSatisfying(BusinessException.class, exception ->
                            assertThat(exception.errorCode()).isEqualTo(ErrorCode.MUSIC_RECOMMENDATION_UNAVAILABLE)
                    );
            verify(credentialService, never()).clear(ownerUserId, MusicPlatform.NETEASE);
        } finally {
            server.stop(0);
        }
    }

    @Test
    void parseUserInfoSupportsAccountResponse() {
        JSONObject payload = JSONObject.parseObject("""
                {
                  "profile": {
                    "userId": 10001,
                    "nickname": "Local Listener",
                    "avatarUrl": "https://example.com/avatar.jpg"
                  },
                  "account": {"vipType": 11}
                }
                """);

        var userInfo = proxy.parseUserInfo(payload);

        assertThat(userInfo.userId()).isEqualTo("10001");
        assertThat(userInfo.nickname()).isEqualTo("Local Listener");
        assertThat(userInfo.vip()).isTrue();
    }

    @Test
    void parseUserInfoSupportsNestedLoginStatusResponse() {
        JSONObject payload = JSONObject.parseObject("""
                {
                  "data": {
                    "account": {"id": 20002, "userName": "Fallback Account"},
                    "profile": {
                      "userId": 20002,
                      "nickname": "Cloud Listener",
                      "avatarUrl": "https://example.com/cloud.jpg"
                    }
                  }
                }
                """);

        var userInfo = proxy.parseUserInfo(payload);

        assertThat(userInfo.userId()).isEqualTo("20002");
        assertThat(userInfo.nickname()).isEqualTo("Cloud Listener");
        assertThat(userInfo.avatarUrl()).isEqualTo("https://example.com/cloud.jpg");
    }

    @Test
    void parseUserInfoFallsBackToAccountIdentity() {
        JSONObject payload = JSONObject.parseObject("""
                {
                  "data": {
                    "account": {"id": 30003, "userName": "Account Only"}
                  }
                }
                """);

        var userInfo = proxy.parseUserInfo(payload);

        assertThat(userInfo.userId()).isEqualTo("30003");
        assertThat(userInfo.nickname()).isEqualTo("Account Only");
    }

    @Test
    void normalizeCookieHeaderRemovesResponseAttributes() {
        String cookie = proxy.normalizeCookieHeader(
                "MUSIC_U=music-token;__csrf=csrf-token; Path=/; Max-Age=3600; HttpOnly; SameSite=Lax"
        );

        assertThat(cookie).isEqualTo("MUSIC_U=music-token; __csrf=csrf-token");
    }

    @Test
    void lyricsIncludeWordLevelPayloadFromExtraEndpoint() throws IOException {
        AtomicReference<String> extraLyricsRequest = new AtomicReference<>();
        HttpServer server = startLyricServer(extraLyricsRequest, exchange ->
                writeJson(exchange, "{\"yrc\":{\"lyric\":\"[16210,3460](16210,670,0)还(16880,410,0)没\"}}"));
        try {
            NeteaseMusicProxy localProxy = new NeteaseMusicProxy(
                    lyricConfigService(server),
                    mock(MusicPlatformCredentialService.class)
            );

            var lyrics = localProxy.getLyrics(UUID.randomUUID(), "song-1");

            assertThat(lyrics.syncedLyrics()).isEqualTo("[00:01.00]line");
            assertThat(lyrics.translatedLyrics()).isEqualTo("[00:01.00]translation");
            assertThat(lyrics.wordLyrics()).isEqualTo("[16210,3460](16210,670,0)还(16880,410,0)没");
            assertThat(extraLyricsRequest.get()).contains("/lyric/new").contains("id=song-1");
        } finally {
            server.stop(0);
        }
    }

    @Test
    void lyricsKeepLineLevelResultWhenExtraEndpointConnectionFails() throws IOException {
        AtomicReference<String> extraLyricsRequest = new AtomicReference<>();
        // 直接关闭连接：客户端读取响应时抛 IOException，逐字载荷降级为不可用。
        HttpServer server = startLyricServer(extraLyricsRequest, HttpExchange::close);
        try {
            NeteaseMusicProxy localProxy = new NeteaseMusicProxy(
                    lyricConfigService(server),
                    mock(MusicPlatformCredentialService.class)
            );

            var lyrics = localProxy.getLyrics(UUID.randomUUID(), "song-1");

            assertThat(lyrics.syncedLyrics()).isEqualTo("[00:01.00]line");
            assertThat(lyrics.translatedLyrics()).isEqualTo("[00:01.00]translation");
            assertThat(lyrics.wordLyrics()).isNull();
            assertThat(extraLyricsRequest.get()).isNotNull();
        } finally {
            server.stop(0);
        }
    }

    @Test
    void lyricsKeepLineLevelResultWhenExtraEndpointReturnsServerError() throws IOException {
        AtomicReference<String> extraLyricsRequest = new AtomicReference<>();
        HttpServer server = startLyricServer(extraLyricsRequest, exchange -> writeStatus(exchange, 500));
        try {
            NeteaseMusicProxy localProxy = new NeteaseMusicProxy(
                    lyricConfigService(server),
                    mock(MusicPlatformCredentialService.class)
            );

            var lyrics = localProxy.getLyrics(UUID.randomUUID(), "song-1");

            assertThat(lyrics.syncedLyrics()).isEqualTo("[00:01.00]line");
            assertThat(lyrics.translatedLyrics()).isEqualTo("[00:01.00]translation");
            assertThat(lyrics.wordLyrics()).isNull();
            assertThat(extraLyricsRequest.get()).isNotNull();
        } finally {
            server.stop(0);
        }
    }

    @Test
    void lyricsKeepLineLevelResultWhenExtraEndpointBodyIsMalformed() throws IOException {
        AtomicReference<String> extraLyricsRequest = new AtomicReference<>();
        HttpServer server = startLyricServer(extraLyricsRequest, exchange ->
                writeJson(exchange, "{\"yrc\":"));
        try {
            NeteaseMusicProxy localProxy = new NeteaseMusicProxy(
                    lyricConfigService(server),
                    mock(MusicPlatformCredentialService.class)
            );

            var lyrics = localProxy.getLyrics(UUID.randomUUID(), "song-1");

            assertThat(lyrics.syncedLyrics()).isEqualTo("[00:01.00]line");
            assertThat(lyrics.wordLyrics()).isNull();
        } finally {
            server.stop(0);
        }
    }

    @Test
    void lyricsMarkWordPayloadUnavailableWhenFieldsAreMissingOrBlank() throws IOException {
        AtomicReference<String> extraLyricsRequest = new AtomicReference<>();
        HttpServer server = startLyricServer(extraLyricsRequest, exchange ->
                writeJson(exchange, "{\"yrc\":{\"lyric\":\"   \"}}"));
        try {
            NeteaseMusicProxy localProxy = new NeteaseMusicProxy(
                    lyricConfigService(server),
                    mock(MusicPlatformCredentialService.class)
            );

            var lyrics = localProxy.getLyrics(UUID.randomUUID(), "song-1");

            assertThat(lyrics.syncedLyrics()).isEqualTo("[00:01.00]line");
            assertThat(lyrics.translatedLyrics()).isEqualTo("[00:01.00]translation");
            assertThat(lyrics.wordLyrics()).isNull();
        } finally {
            server.stop(0);
        }
    }

    @Test
    void confirmedQrLoginSavesCookieAndDefersProfileFetch() throws IOException {
        MusicRuntimeConfigService configService = mock(MusicRuntimeConfigService.class);
        MusicPlatformCredentialService credentialService = mock(MusicPlatformCredentialService.class);
        HttpServer server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        AtomicReference<String> profileCookie = new AtomicReference<>();
        server.createContext("/", exchange -> {
            String path = exchange.getRequestURI().getPath();
            String response;
            if ("/login/qr/check".equals(path)) {
                exchange.getResponseHeaders().add(
                        "Set-Cookie",
                        "MUSIC_U=test-cookie; Path=/; HttpOnly"
                );
                exchange.getResponseHeaders().add(
                        "Set-Cookie",
                        "__csrf=csrf-token; Path=/; SameSite=Lax"
                );
                response = "{\"code\":803,\"cookie\":\"MUSIC_U=test-cookie;__csrf=csrf-token\"}";
            } else if ("/user/account".equals(path)) {
                profileCookie.set(exchange.getRequestHeaders().getFirst("Cookie"));
                response = "{\"code\":200,\"profile\":null}";
            } else if ("/login/status".equals(path)) {
                profileCookie.set(exchange.getRequestHeaders().getFirst("Cookie"));
                response = """
                        {"data":{"account":{"id":40004},"profile":{
                        "userId":40004,"nickname":"QR Listener","avatarUrl":"https://example.com/qr.jpg"}}}
                        """;
            } else {
                response = "{\"code\":404}";
            }
            writeJson(exchange, response);
        });
        server.start();
        try {
            when(configService.neteaseBaseUrl()).thenReturn(
                    "http://127.0.0.1:" + server.getAddress().getPort()
            );
            NeteaseMusicProxy localProxy = new NeteaseMusicProxy(configService, credentialService);
            UUID ownerUserId = UUID.randomUUID();

            var status = localProxy.checkQrLogin(ownerUserId, "login-key");

            assertThat(status.status()).isEqualTo("confirmed");
            // 资料拉取改为确认后的 getUserInfo 异步完成，确认阶段不得串行请求资料接口
            assertThat(profileCookie.get()).isNull();
            assertThat(status.userInfo().userId()).isBlank();
            verify(credentialService).save(
                    eq(ownerUserId),
                    eq(MusicPlatform.NETEASE),
                    argThat(cookie -> cookie.contains("MUSIC_U=test-cookie")
                            && cookie.contains("__csrf=csrf-token")
                            && !cookie.contains("Path")),
                    eq(status.userInfo())
            );
        } finally {
            server.stop(0);
        }
    }

    @Test
    void confirmedQrLoginPersistsCredentialWhenProfileIsTemporarilyUnavailable() throws IOException {
        MusicRuntimeConfigService configService = mock(MusicRuntimeConfigService.class);
        MusicPlatformCredentialService credentialService = mock(MusicPlatformCredentialService.class);
        HttpServer server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/", exchange -> {
            String path = exchange.getRequestURI().getPath();
            String response = "/login/qr/check".equals(path)
                    ? "{\"code\":803,\"cookie\":\"MUSIC_U=temporary-cookie;Path=/;HttpOnly\"}"
                    : "{\"code\":200,\"profile\":null,\"account\":null}";
            writeJson(exchange, response);
        });
        server.start();
        try {
            when(configService.neteaseBaseUrl()).thenReturn(
                    "http://127.0.0.1:" + server.getAddress().getPort()
            );
            NeteaseMusicProxy localProxy = new NeteaseMusicProxy(configService, credentialService);
            UUID ownerUserId = UUID.randomUUID();

            var status = localProxy.checkQrLogin(ownerUserId, "login-key");

            assertThat(status.status()).isEqualTo("confirmed");
            assertThat(status.userInfo().nickname()).isEqualTo("网易云账号");
            verify(credentialService).save(
                    eq(ownerUserId),
                    eq(MusicPlatform.NETEASE),
                    eq("MUSIC_U=temporary-cookie"),
                    eq(status.userInfo())
            );
        } finally {
            server.stop(0);
        }
    }

    private static void writeJson(HttpExchange exchange, String response) throws IOException {
        byte[] body = response.getBytes(StandardCharsets.UTF_8);
        exchange.getResponseHeaders().set("Content-Type", "application/json; charset=utf-8");
        exchange.sendResponseHeaders(200, body.length);
        try (OutputStream responseBody = exchange.getResponseBody()) {
            responseBody.write(body);
        }
    }

    private static void writeStatus(HttpExchange exchange, int status) throws IOException {
        exchange.sendResponseHeaders(status, -1);
        exchange.close();
    }

    /**
     * 启动仅服务歌词接口的本地 HTTP 服务：/lyric 固定返回行级歌词，/lyric/new 由调用方决定响应。
     *
     * @param extraLyricsRequest 记录 /lyric/new 实际请求地址
     * @param extraLyricsHandler /lyric/new 响应处理
     * @return 已启动的服务
     */
    private static HttpServer startLyricServer(
            AtomicReference<String> extraLyricsRequest,
            HttpHandler extraLyricsHandler
    ) throws IOException {
        HttpServer server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/", exchange -> {
            if ("/lyric/new".equals(exchange.getRequestURI().getPath())) {
                extraLyricsRequest.set(exchange.getRequestURI().toString());
                extraLyricsHandler.handle(exchange);
                return;
            }
            writeJson(exchange, """
                    {"lrc":{"lyric":"[00:01.00]line"},"tlyric":{"lyric":"[00:01.00]translation"}}
                    """);
        });
        server.start();
        return server;
    }

    private static MusicRuntimeConfigService lyricConfigService(HttpServer server) {
        MusicRuntimeConfigService configService = mock(MusicRuntimeConfigService.class);
        when(configService.onlineEnabled()).thenReturn(true);
        when(configService.neteaseEnabled()).thenReturn(true);
        when(configService.neteaseBaseUrl()).thenReturn(
                "http://127.0.0.1:" + server.getAddress().getPort()
        );
        return configService;
    }

    private static MusicPlatformCredential credential(String externalUserId) {
        return new MusicPlatformCredential(
                "MUSIC_U=test-cookie",
                externalUserId,
                new PlatformUserInfo("netease", externalUserId, "Listener", "", false),
                Instant.now()
        );
    }
}
