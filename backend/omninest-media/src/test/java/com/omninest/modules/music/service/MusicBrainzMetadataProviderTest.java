package com.omninest.modules.music.service;

import org.junit.jupiter.api.Disabled;
import com.sun.net.httpserver.HttpServer;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.security.SafeUrlValidator;
import com.omninest.modules.music.dto.MusicDtos.MusicScrapeCandidateDto;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.omninest.modules.music.domain.MusicTrack;
import java.lang.reflect.Field;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.net.InetSocketAddress;
import java.net.http.HttpClient;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;

class MusicBrainzMetadataProviderTest {
    private final MusicRuntimeConfigService configService = mock(MusicRuntimeConfigService.class);
    private final SafeUrlValidator safeUrlValidator = mock(SafeUrlValidator.class);
    private HttpServer server;

    @AfterEach
    void tearDown() {
        if (server != null) {
            server.stop(0);
        }
    }

    @Test
    void sharedClientNeverFollowsRedirects() throws Exception {
        Field field = MusicBrainzMetadataProvider.class.getDeclaredField("httpClient");
        field.setAccessible(true);
        HttpClient client = (HttpClient) field.get(new MusicBrainzMetadataProvider(configService, safeUrlValidator));

        assertThat(client.followRedirects()).isEqualTo(HttpClient.Redirect.NEVER);
    }

    @Test
    void requestUriRejectsMetadataServiceBaseUrl() throws Exception {
        when(configService.musicBrainzBaseUrl()).thenReturn("http://169.254.169.254/ws/2");
        Method method = MusicBrainzMetadataProvider.class.getDeclaredMethod("uri", String.class, Map.class);
        method.setAccessible(true);

        assertThatThrownBy(() -> method.invoke(
                new MusicBrainzMetadataProvider(configService, safeUrlValidator), "/release", Map.of()))
                .isInstanceOf(InvocationTargetException.class)
                .cause()
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("元数据服务");
    }

    @Test
    void requestUriRejectsOriginResolvingToRestrictedSegment() throws Exception {
        when(configService.musicBrainzBaseUrl()).thenReturn("https://musicbrainz.example/ws/2");
        doThrow(new BusinessException(ErrorCode.BAD_REQUEST, "URL 不能指向本地或内网地址"))
                .when(safeUrlValidator)
                .requireSelfHostedSafeHost(any());
        MusicBrainzMetadataProvider provider = new MusicBrainzMetadataProvider(configService, safeUrlValidator);
        Method method = MusicBrainzMetadataProvider.class.getDeclaredMethod("uri", String.class, Map.class);
        method.setAccessible(true);

        assertThatThrownBy(() -> method.invoke(provider, "/release", Map.of()))
                .isInstanceOf(InvocationTargetException.class)
                .cause()
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("内网地址");
    }

    @Test
    void searchReturnsRankedCandidateFromMusicBrainzReleaseLookup() throws Exception {
        server = HttpServer.create(new InetSocketAddress(0), 0);
        server.createContext("/ws/2/release/", exchange -> {
            String path = exchange.getRequestURI().getPath();
            String body;
            if (path.endsWith("/release/")) {
                body = """
                        {"releases":[{"id":"rel-1","title":"City Lights","score":95,"date":"2024-01-02","artist-credit":[{"name":"Omni Band","artist":{"id":"artist-1","name":"Omni Band"}}],"release-group":{"id":"rg-1"}}]}
                        """;
            } else {
                body = """
                        {"id":"rel-1","title":"City Lights","date":"2024-01-02","artist-credit":[{"name":"Omni Band","artist":{"id":"artist-1","name":"Omni Band"}}],"release-group":{"id":"rg-1"},"media":[{"position":1,"tracks":[{"position":1,"number":"1","title":"Night Drive","length":245000,"recording":{"id":"rec-1","title":"Night Drive"}}]}]}
                        """;
            }
            byte[] bytes = body.getBytes(StandardCharsets.UTF_8);
            exchange.getResponseHeaders().add("Content-Type", "application/json; charset=utf-8");
            exchange.sendResponseHeaders(200, bytes.length);
            try (var os = exchange.getResponseBody()) {
                os.write(bytes);
            }
        });
        server.start();

        when(configService.metadataProvidersEnabled()).thenReturn(true);
        when(configService.musicBrainzEnabled()).thenReturn(true);
        when(configService.musicBrainzBaseUrl()).thenReturn("http://localhost:" + server.getAddress().getPort() + "/ws/2");
        when(configService.musicBrainzUserAgent()).thenReturn("OmniNestTest/1.0");
        when(configService.musicBrainzRequestDelayMs()).thenReturn(0L);
        when(configService.musicBrainzCoverBaseUrl()).thenReturn("https://coverartarchive.org/release");

        MusicBrainzMetadataProvider provider = new MusicBrainzMetadataProvider(configService, safeUrlValidator);
        MusicTrack track = new MusicTrack();
        track.setId(UUID.fromString("10000000-0000-0000-0000-000000000001"));
        track.setTitle("Night Drive");
        track.setArtistName("Omni Band");
        track.setAlbumTitle("City Lights");
        track.setDurationSeconds(245);
        track.setTrackNumber(1);
        track.setDiscNumber(1);

        List<MusicScrapeCandidateDto> candidates = provider.search(track);

        assertThat(candidates).hasSize(1);
        var candidate = candidates.get(0);
        assertThat(candidate.externalId()).isEqualTo("rec-1");
        assertThat(candidate.coverUrl()).isEqualTo("https://coverartarchive.org/release/rel-1/front-500");
        assertThat(candidate.artistName()).isEqualTo("Omni Band");
        assertThat(candidate.albumTitle()).isEqualTo("City Lights");
        assertThat(candidate.trackNumber()).isEqualTo(1);
        assertThat(candidate.discNumber()).isEqualTo(1);
        assertThat(candidate.score()).isGreaterThanOrEqualTo(75);
    }

    /**
     * 模拟无标签 FLAC 文件导入后的刮削场景。
     * title = 文件名（含 artist 和 album 信息），artist = "Unknown Artist"，album = "Unknown Album"。
     * 验证：MusicBrainz 查询能命中结果。
     */
    /**
     * 用真实 MusicBrainz API 测试：无标签文件（title=文件名, artist="Unknown Artist"）能否刮削到结果。
     * 此测试会实际调用 musicbrainz.org，受网络和速率限制影响。
     */
    @Disabled("需要网络访问 musicbrainz.org，手动运行时取消此注解")
    @Test
    void realMusicBrainzSearchForFilenameBasedTrack() throws Exception {
        when(configService.metadataProvidersEnabled()).thenReturn(true);
        when(configService.musicBrainzEnabled()).thenReturn(true);
        when(configService.musicBrainzBaseUrl()).thenReturn("https://musicbrainz.org/ws/2");
        when(configService.musicBrainzUserAgent()).thenReturn("OmniNestTest/1.0 (test@example.com)");
        when(configService.musicBrainzRequestDelayMs()).thenReturn(1100L);

        MusicBrainzMetadataProvider provider = new MusicBrainzMetadataProvider(configService, safeUrlValidator);

        // 场景1：无标签文件（当前行为：title=文件名, artist=Unknown）
        MusicTrack trackNoTags = new MusicTrack();
        trackNoTags.setId(UUID.fromString("10000000-0000-0000-0000-000000000002"));
        trackNoTags.setTitle("偏爱 - 张芸京[破天荒]");
        trackNoTags.setArtistName("Unknown Artist");
        trackNoTags.setAlbumTitle("Unknown Album");

        List<MusicScrapeCandidateDto> candidatesNoTags = provider.search(trackNoTags);

        // 场景2：正确解析后的状态（理想情况）
        MusicTrack trackParsed = new MusicTrack();
        trackParsed.setId(UUID.fromString("10000000-0000-0000-0000-000000000003"));
        trackParsed.setTitle("偏爱");
        trackParsed.setArtistName("张芸京");
        trackParsed.setAlbumTitle("破天荒");

        List<MusicScrapeCandidateDto> candidatesParsed = provider.search(trackParsed);

        // 解析后应该能找到高分匹配
        assertThat(candidatesParsed).as("解析后刮削候选").isNotEmpty();
        assertThat(candidatesParsed.get(0).score()).isGreaterThanOrEqualTo(75);
    }
}
