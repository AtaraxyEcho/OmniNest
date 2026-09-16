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

    private static MusicPlatformCredential credential(String externalUserId) {
        return new MusicPlatformCredential(
                "MUSIC_U=test-cookie",
                externalUserId,
                new PlatformUserInfo("netease", externalUserId, "Listener", "", false),
                Instant.now()
        );
    }
}
