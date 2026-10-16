package com.omninest.modules.music.service;

import com.omninest.common.json.JsonSupport;
import com.omninest.common.security.OutboundEndpointRules;
import com.omninest.common.security.SafeUrlValidator;
import java.io.IOException;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;
import tools.jackson.databind.JsonNode;

/**
 * LRCLIB 歌词搜索服务。
 * LRCLIB (lrclib.net) 是开源免费歌词 API，无需 API Key，国内可访问。
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class LrclibLyricsService {
    private static final String BASE_URL = "https://lrclib.net/api";
    private static final Duration TIMEOUT = Duration.ofSeconds(15);
    private static final String USER_AGENT = "OmniNest/0.1.0 (https://github.com/omninest)";

    private final SafeUrlValidator safeUrlValidator;

    private final HttpClient httpClient = HttpClient.newBuilder()
            .connectTimeout(TIMEOUT)
            .followRedirects(HttpClient.Redirect.NEVER)
            .build();

    /**
     * 搜索歌词。
     *
     * @param artistName 艺术家名
     * @param trackTitle 曲目标题
     * @param albumName  专辑名（可选，提高匹配精度）
     * @return 最佳匹配的歌词结果，无匹配返回 null
     */
    public LyricsResult search(String artistName, String trackTitle, String albumName) {
        if (isBlank(artistName) || isBlank(trackTitle)) {
            return null;
        }
        try {
            // 优先用精确搜索
            LyricsResult exact = searchExact(artistName, trackTitle, albumName);
            if (exact != null) {
                return exact;
            }
            // 回退到模糊搜索
            return searchFuzzy(artistName + " " + trackTitle);
        } catch (InterruptedException ex) {
            Thread.currentThread().interrupt();
            log.warn("LRCLIB 请求被中断");
            return null;
        } catch (IOException | RuntimeException ex) {
            log.warn("LRCLIB 请求异常: errorType={}", ex.getClass().getSimpleName());
            return null;
        }
    }

    /**
     * 精确搜索: GET /api/get?artist_name=X&track_name=Y&album_name=Z
     */
    private LyricsResult searchExact(String artistName, String trackTitle, String albumName)
            throws IOException, InterruptedException {
        StringBuilder params = new StringBuilder();
        params.append("artist_name=").append(encode(artistName));
        params.append("&track_name=").append(encode(trackTitle));
        if (!isBlank(albumName)) {
            params.append("&album_name=").append(encode(albumName));
        }
        JsonNode json = get("/get?" + params);
        if (json == null) {
            return null;
        }
        return parseResult(json);
    }

    /**
     * 模糊搜索: GET /api/search?q=X+Y
     */
    private LyricsResult searchFuzzy(String query) throws IOException, InterruptedException {
        JsonNode results = getArray("/search?q=" + encode(query));
        if (results == null || !results.isArray() || results.isEmpty()) {
            return null;
        }
        // 取第一个结果
        return parseResult(results.get(0));
    }

    private LyricsResult parseResult(JsonNode json) {
        String plainLyrics = json.path("plainLyrics").asString(null);
        String syncedLyrics = json.path("syncedLyrics").asString(null);
        String trackName = json.path("trackName").asString(null);
        String artistName = json.path("artistName").asString(null);
        String albumName = json.path("albumName").asString(null);
        if (isBlank(plainLyrics) && isBlank(syncedLyrics)) {
            return null;
        }
        return new LyricsResult(plainLyrics, syncedLyrics, trackName, artistName, albumName);
    }

    /**
     * 拼出请求地址并按内置公网服务校验；基址是编译期常量，仍逐次复核以拒绝任何解析到受限地址的结果。
     */
    private URI safeUri(String path) {
        return OutboundEndpointRules.requirePublicEndpoint(URI.create(BASE_URL + path), safeUrlValidator);
    }

    private JsonNode get(String path) throws IOException, InterruptedException {
        HttpRequest request = HttpRequest.newBuilder(safeUri(path))
                .timeout(TIMEOUT)
                .header("User-Agent", USER_AGENT)
                .header("Accept", "application/json")
                .GET()
                .build();
        HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
        if (response.statusCode() == 404) {
            return null;
        }
        if (response.statusCode() < 200 || response.statusCode() >= 300) {
            log.warn("LRCLIB 请求失败: status={}, path={}", response.statusCode(), path);
            return null;
        }
        return JsonSupport.readTree(response.body());
    }

    private JsonNode getArray(String path) throws IOException, InterruptedException {
        HttpRequest request = HttpRequest.newBuilder(safeUri(path))
                .timeout(TIMEOUT)
                .header("User-Agent", USER_AGENT)
                .header("Accept", "application/json")
                .GET()
                .build();
        HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
        if (response.statusCode() < 200 || response.statusCode() >= 300) {
            log.warn("LRCLIB 请求失败: status={}, path={}", response.statusCode(), path);
            return null;
        }
        return JsonSupport.readTree(response.body());
    }

    private String encode(String value) {
        return URLEncoder.encode(value == null ? "" : value, StandardCharsets.UTF_8);
    }

    private boolean isBlank(String value) {
        return value == null || value.isBlank();
    }

    /**
     * 歌词搜索结果。
     *
     * @param plainLyrics  纯文本歌词
     * @param syncedLyrics LRC 格式同步歌词（带时间戳）
     * @param trackName    曲目名
     * @param artistName   艺术家名
     * @param albumName    专辑名
     */
    public record LyricsResult(
            String plainLyrics,
            String syncedLyrics,
            String trackName,
            String artistName,
            String albumName
    ) {
    }
}
