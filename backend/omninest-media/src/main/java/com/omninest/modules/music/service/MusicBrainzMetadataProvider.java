package com.omninest.modules.music.service;

import com.omninest.common.json.JsonSupport;
import com.omninest.modules.music.domain.MusicTrack;
import com.omninest.modules.music.dto.MusicDtos.MusicScrapeCandidateDto;
import java.io.IOException;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.LocalDate;
import java.time.format.DateTimeParseException;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;
import tools.jackson.databind.JsonNode;

@Slf4j
@Component
@RequiredArgsConstructor
public class MusicBrainzMetadataProvider implements MusicMetadataProvider {
    private static final int MAX_SEARCH_RESULTS = 8;
    private static final Duration REQUEST_TIMEOUT = Duration.ofSeconds(10);

    private final MusicRuntimeConfigService configService;
    private final HttpClient httpClient = HttpClient.newBuilder()
            .connectTimeout(REQUEST_TIMEOUT)
            .followRedirects(HttpClient.Redirect.NORMAL)
            .build();

    private final Object throttleLock = new Object();
    private long lastRequestAt;

    @Override
    public String providerName() {
        return "MusicBrainz";
    }

    @Override
    public List<MusicScrapeCandidateDto> search(MusicTrack track) {
        if (!enabled()) {
            log.debug("MusicBrainz 未启用，跳过: trackId={}", track.getId());
            return List.of();
        }
        List<String> queries = searchQueries(track);
        if (queries.isEmpty()) {
            log.debug("无可构建的搜索查询: trackId={}", track.getId());
            return List.of();
        }
        log.info("MusicBrainz 开始搜索: trackId={}, 查询策略={} 条", track.getId(), queries.size());
        try {
            // 依次尝试所有候选查询，收集并集（按 release ID 去重）
            Set<String> seenReleaseIds = new HashSet<>();
            List<ReleaseSearchResult> allSearchResults = new ArrayList<>();
            for (int i = 0; i < queries.size(); i++) {
                String query = queries.get(i);
                List<ReleaseSearchResult> searchResults = searchReleases(query);
                log.debug("MusicBrainz 查询完成: queryIndex={}, resultCount={}", i, searchResults.size());
                for (ReleaseSearchResult result : searchResults) {
                    if (seenReleaseIds.add(result.id())) {
                        allSearchResults.add(result);
                    }
                }
                // 已经找到足够候选，无需继续尝试更宽松的查询
                if (allSearchResults.size() >= MAX_SEARCH_RESULTS) {
                    log.debug("  已达 {} 个候选上限，跳过剩余查询", MAX_SEARCH_RESULTS);
                    break;
                }
            }
            if (allSearchResults.isEmpty()) {
                log.info("MusicBrainz 搜索无结果: trackId={}", track.getId());
                return List.of();
            }
            log.info("去重后共 {} 个 release，开始逐个 lookup 并评分...", allSearchResults.size());
            List<MusicScrapeCandidateDto> candidates = new ArrayList<>();
            for (ReleaseSearchResult result : allSearchResults) {
                ReleaseDetail detail = lookupRelease(result.id());
                if (detail == null) {
                    log.debug("  release lookup 失败: id={}", result.id());
                    continue;
                }
                MusicScrapeCandidateDto candidate = toCandidate(track, result, detail);
                if (candidate != null) {
                    candidates.add(candidate);
                    log.debug("MusicBrainz 候选生成: trackId={}, score={}", track.getId(), candidate.score());
                }
            }
            candidates.sort((left, right) -> Integer.compare(right.score(), left.score()));
            if (!candidates.isEmpty()) {
                MusicScrapeCandidateDto best = candidates.get(0);
                log.info("MusicBrainz 搜索完成: trackId={}, 候选数={}, 最佳 score={}",
                        track.getId(), candidates.size(), best.score());
            } else {
                log.info("MusicBrainz 搜索完成: trackId={}, 所有 release 评分不足，无有效候选", track.getId());
            }
            return candidates;
        } catch (InterruptedException ex) {
            Thread.currentThread().interrupt();
            log.warn("MusicBrainz 请求被中断: trackId={}", track.getId());
            return List.of();
        } catch (IOException | RuntimeException ex) {
            log.warn("MusicBrainz 请求异常: trackId={}, errorType={}",
                    track.getId(), ex.getClass().getSimpleName());
            return List.of();
        }
    }

    private boolean enabled() {
        return configService.metadataProvidersEnabled() && configService.musicBrainzEnabled();
    }

    private List<ReleaseSearchResult> searchReleases(String query) throws IOException, InterruptedException {
        URI uri = uri("/release/", Map.of(
                "query", query,
                "fmt", "json",
                "limit", String.valueOf(MAX_SEARCH_RESULTS),
                "offset", "0"
        ));
        JsonNode json = requestJson(uri);
        if (json == null) {
            return List.of();
        }
        JsonNode releases = json.path("releases");
        if (!releases.isArray() || releases.isEmpty()) {
            return List.of();
        }
        List<ReleaseSearchResult> results = new ArrayList<>();
        for (int index = 0; index < releases.size() && results.size() < MAX_SEARCH_RESULTS; index++) {
            JsonNode item = releases.get(index);
            String id = text(item, "id");
            String title = text(item, "title");
            if (id.isBlank() || title.isBlank()) {
                continue;
            }
            results.add(new ReleaseSearchResult(
                    id,
                    title,
                    artistCreditName(item.path("artist-credit")),
                    parseDate(text(item, "date")),
                    item.path("score").asInt(),
                    releaseGroupId(item),
                    releaseArtistId(item.path("artist-credit"))
            ));
        }
        return results;
    }

    private ReleaseDetail lookupRelease(String releaseId) throws IOException, InterruptedException {
        URI uri = uri("/release/" + releaseId, Map.of(
                "inc", "recordings+artist-credits+release-groups+media+tags+genres",
                "fmt", "json"
        ));
        JsonNode json = requestJson(uri);
        if (json == null) {
            return null;
        }
        return parseReleaseDetail(json);
    }

    private MusicScrapeCandidateDto toCandidate(MusicTrack track, ReleaseSearchResult result, ReleaseDetail detail) {
        TrackMatch match = bestTrackMatch(track, detail);
        if (match == null) {
            return null;
        }
        int score = Math.min(100, Math.max(0, (result.score() + match.score()) / 2));
        Map<String, Object> externalIds = new LinkedHashMap<>();
        externalIds.put("musicbrainzRecordingId", match.recordingId());
        externalIds.put("musicbrainzReleaseId", detail.releaseId());
        if (detail.releaseGroupId() != null) {
            externalIds.put("musicbrainzReleaseGroupId", detail.releaseGroupId());
        }
        if (detail.artistId() != null) {
            externalIds.put("musicbrainzArtistId", detail.artistId());
        }

        Map<String, Object> providerMetadata = new LinkedHashMap<>();
        providerMetadata.put("provider", providerName());
        providerMetadata.put("searchQuery", buildQuery(track));
        providerMetadata.put("releaseTitle", detail.title());
        providerMetadata.put("artistName", detail.artistName());
        providerMetadata.put("matchedTrackTitle", match.title());
        providerMetadata.put("releaseScore", result.score());
        providerMetadata.put("trackScore", match.score());
        providerMetadata.put("matchReasons", match.reasons());
        providerMetadata.put("releaseGroupId", detail.releaseGroupId());
        providerMetadata.put("releaseArtistId", detail.artistId());
        providerMetadata.put("coverUrl", coverUrl(detail.releaseId()));

        return new MusicScrapeCandidateDto(
                providerName(),
                match.recordingId(),
                match.title(),
                detail.artistName(),
                detail.title(),
                detail.releaseDate(),
                match.durationSeconds(),
                match.trackNumber(),
                match.discNumber(),
                coverUrl(detail.releaseId()),
                score,
                detail.genre(),
                externalIds,
                providerMetadata
        );
    }

    private TrackMatch bestTrackMatch(MusicTrack track, ReleaseDetail detail) {
        TrackMatch best = null;
        for (ReleaseTrack releaseTrack : detail.tracks()) {
            int score = 0;
            List<String> reasons = new ArrayList<>();
            if (equalsNormalized(track.getTitle(), releaseTrack.title())) {
                score += 40;
                reasons.add("title");
            } else {
                int titleScore = similarityScore(track.getTitle(), releaseTrack.title());
                score += titleScore;
                if (titleScore > 0) {
                    reasons.add("title~" + titleScore);
                }
            }
            if (equalsNormalized(track.getArtistName(), detail.artistName())) {
                score += 20;
                reasons.add("artist");
            } else {
                int artistScore = similarityScore(track.getArtistName(), detail.artistName());
                score += Math.min(20, artistScore / 2);
                if (artistScore > 0) {
                    reasons.add("artist~" + artistScore);
                }
            }
            if (equalsNormalized(track.getAlbumTitle(), detail.title())) {
                score += 15;
                reasons.add("album");
            } else {
                int albumScore = similarityScore(track.getAlbumTitle(), detail.title());
                score += Math.min(15, albumScore / 2);
                if (albumScore > 0) {
                    reasons.add("album~" + albumScore);
                }
            }
            score += durationScore(track.getDurationSeconds(), releaseTrack.durationSeconds());
            if (track.getTrackNumber() != null && releaseTrack.trackNumber() != null && track.getTrackNumber().equals(releaseTrack.trackNumber())) {
                score += 8;
                reasons.add("trackNumber");
            }
            if (track.getDiscNumber() != null && releaseTrack.discNumber() != null && track.getDiscNumber().equals(releaseTrack.discNumber())) {
                score += 4;
                reasons.add("discNumber");
            }
            if (best == null || score > best.score()) {
                best = new TrackMatch(
                        releaseTrack.recordingId(),
                        releaseTrack.title(),
                        releaseTrack.trackNumber(),
                        releaseTrack.discNumber(),
                        releaseTrack.durationSeconds(),
                        score,
                        reasons
                );
            }
        }
        if (best == null || best.score() < 40) {
            return null;
        }
        return best;
    }

    private ReleaseDetail parseReleaseDetail(JsonNode json) {
        String releaseId = text(json, "id");
        String title = text(json, "title");
        String releaseGroupId = releaseGroupId(json);
        String artistId = releaseArtistId(json.path("artist-credit"));
        String artistName = artistCreditName(json.path("artist-credit"));
        LocalDate releaseDate = parseDate(text(json, "date"));
        List<ReleaseTrack> tracks = new ArrayList<>();
        JsonNode media = json.path("media");
        if (media.isArray()) {
            for (int mediumIndex = 0; mediumIndex < media.size(); mediumIndex++) {
                JsonNode medium = media.get(mediumIndex);
                Integer discNumber = medium.path("position").asInt();
                JsonNode trackArray = medium.path("tracks");
                if (!trackArray.isArray()) {
                    continue;
                }
                for (int trackIndex = 0; trackIndex < trackArray.size(); trackIndex++) {
                    JsonNode track = trackArray.get(trackIndex);
                    String trackTitle = text(track, "title");
                    if (trackTitle.isBlank()) {
                        continue;
                    }
                    Integer trackNumber = parseInteger(track.path("number").asString(null));
                    if (trackNumber == null) {
                        trackNumber = track.path("position").asInt();
                    }
                    JsonNode recording = track.path("recording");
                    String recordingId = recording.isObject() ? text(recording, "id") : text(track, "id");
                    tracks.add(new ReleaseTrack(
                            recordingId,
                            trackTitle,
                            trackNumber,
                            discNumber,
                            durationSeconds(track.hasNonNull("length") ? track.path("length").asInt() : null)
                    ));
                }
            }
        }
        // 解析 genre: 优先取 release-group 的 genres，其次 release 的 tags
        JsonNode releaseGroup = releaseGroupId != null ? json.path("release-group") : null;
        String genre = parseGenre(json, releaseGroup);
        return new ReleaseDetail(releaseId, title, releaseGroupId, artistId, artistName, releaseDate, tracks, genre);
    }

    /**
     * 从 MusicBrainz release JSON 中提取 genre。
     * 优先取 release-group.genres[0].name，其次 release.tags[0].name。
     */
    private String parseGenre(JsonNode releaseJson, JsonNode releaseGroup) {
        // 优先 release-group 的 genres（更权威）
        if (releaseGroup != null && releaseGroup.isObject()) {
            JsonNode genres = releaseGroup.path("genres");
            if (genres.isArray() && !genres.isEmpty()) {
                String name = text(genres.get(0), "name");
                if (!name.isBlank()) return name;
            }
        }
        // 其次 release 的 tags
        JsonNode tags = releaseJson.path("tags");
        if (tags.isArray() && !tags.isEmpty()) {
            String name = text(tags.get(0), "name");
            if (!name.isBlank()) return name;
        }
        return null;
    }

    private int durationScore(Integer left, Integer right) {
        if (left == null || right == null || left <= 0 || right <= 0) {
            return 0;
        }
        int diff = Math.abs(left - right);
        if (diff <= 2) {
            return 12;
        }
        if (diff <= 5) {
            return 10;
        }
        if (diff <= 10) {
            return 6;
        }
        if (diff <= 15) {
            return 3;
        }
        return 0;
    }

    private List<String> searchQueries(MusicTrack track) {
        LinkedHashSet<String> queries = new LinkedHashSet<>();
        String artist = normalize(track.getArtistName());
        String album = normalize(track.getAlbumTitle());
        String title = normalize(track.getTitle());
        if (!artist.isBlank() && hasRealAlbum(album)) {
            queries.add("artist:\"" + escapeQuery(artist) + "\" AND release:\"" + escapeQuery(album) + "\"");
        }
        if (!artist.isBlank() && !title.isBlank()) {
            queries.add("artist:\"" + escapeQuery(artist) + "\" AND recording:\"" + escapeQuery(title) + "\"");
        }
        if (!artist.isBlank()) {
            queries.add("artist:\"" + escapeQuery(artist) + "\"");
        }
        if (!title.isBlank()) {
            queries.add("recording:\"" + escapeQuery(title) + "\"");
        }
        return new ArrayList<>(queries);
    }

    private String buildQuery(MusicTrack track) {
        List<String> queries = searchQueries(track);
        return queries.isEmpty() ? "" : queries.get(0);
    }

    private String coverUrl(String releaseId) {
        if (releaseId == null || releaseId.isBlank()) {
            return null;
        }
        String baseUrl = trimTrailingSlash(configService.musicBrainzCoverBaseUrl());
        if (baseUrl.isBlank()) {
            return null;
        }
        return baseUrl + "/" + releaseId + "/front-500";
    }

    private JsonNode requestJson(URI uri) throws IOException, InterruptedException {
        throttle();
        HttpRequest request = HttpRequest.newBuilder(uri)
                .timeout(REQUEST_TIMEOUT)
                .header("User-Agent", configService.musicBrainzUserAgent())
                .header("Accept", "application/json")
                .GET()
                .build();
        HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
        if (response.statusCode() < 200 || response.statusCode() >= 300) {
            log.warn("MusicBrainz 请求失败: status={}, uri={}", response.statusCode(), uri);
            return null;
        }
        return JsonSupport.readTree(response.body());
    }

    private void throttle() throws InterruptedException {
        long delay = Math.max(0L, configService.musicBrainzRequestDelayMs());
        if (delay <= 0L) {
            return;
        }
        synchronized (throttleLock) {
            long now = System.currentTimeMillis();
            long wait = lastRequestAt + delay - now;
            if (wait > 0L) {
                Thread.sleep(wait);
            }
            lastRequestAt = System.currentTimeMillis();
        }
    }

    private URI uri(String path, Map<String, String> params) {
        String baseUrl = trimTrailingSlash(configService.musicBrainzBaseUrl());
        StringBuilder builder = new StringBuilder(baseUrl).append(path);
        if (!params.isEmpty()) {
            builder.append('?');
            boolean first = true;
            for (Map.Entry<String, String> entry : params.entrySet()) {
                if (!first) {
                    builder.append('&');
                }
                builder.append(url(entry.getKey())).append('=').append(url(entry.getValue()));
                first = false;
            }
        }
        return URI.create(builder.toString());
    }

    private String normalize(String value) {
        return value == null ? "" : value.replaceAll("[\\p{Punct}]+", " ").replaceAll("\\s+", " ").trim();
    }

    private String escapeQuery(String value) {
        return value.replace("\"", "\\\"");
    }

    private boolean equalsNormalized(String left, String right) {
        return !normalize(left).isBlank() && normalize(left).equalsIgnoreCase(normalize(right));
    }

    private int similarityScore(String left, String right) {
        String normalizedLeft = normalize(left).toLowerCase(Locale.ROOT);
        String normalizedRight = normalize(right).toLowerCase(Locale.ROOT);
        if (normalizedLeft.isBlank() || normalizedRight.isBlank()) {
            return 0;
        }
        if (normalizedLeft.equals(normalizedRight)) {
            return 30;
        }
        if (normalizedLeft.contains(normalizedRight) || normalizedRight.contains(normalizedLeft)) {
            return 18;
        }
        int common = 0;
        for (String token : normalizedLeft.split("\\s+")) {
            if (token.length() < 2) {
                continue;
            }
            if (normalizedRight.contains(token)) {
                common++;
            }
        }
        return Math.min(14, common * 3);
    }

    private String text(JsonNode item, String key) {
        String value = item.path(key).asString(null);
        return value == null ? "" : value.trim();
    }

    private Integer parseInteger(String value) {
        if (value == null || value.isBlank()) {
            return null;
        }
        try {
            return Integer.parseInt(value.trim());
        } catch (NumberFormatException ex) {
            return null;
        }
    }

    private int durationSeconds(Integer milliseconds) {
        if (milliseconds == null || milliseconds <= 0) {
            return 0;
        }
        return Math.max(0, milliseconds / 1000);
    }

    private LocalDate parseDate(String value) {
        if (value == null || value.isBlank()) {
            return null;
        }
        try {
            if (value.length() >= 10) {
                return LocalDate.parse(value.substring(0, 10));
            }
            if (value.length() == 4) {
                return LocalDate.of(Integer.parseInt(value), 1, 1);
            }
            return LocalDate.parse(value);
        } catch (DateTimeParseException | NumberFormatException ex) {
            return null;
        }
    }

    private boolean hasRealAlbum(String album) {
        if (album == null || album.isBlank()) {
            return false;
        }
        String normalized = album.trim().toLowerCase(Locale.ROOT);
        return !"unknown album".equals(normalized) && !"未知专辑".equals(normalized);
    }

    private String releaseGroupId(JsonNode item) {
        JsonNode releaseGroup = item.path("release-group");
        return releaseGroup.isObject() ? text(releaseGroup, "id") : null;
    }

    private String releaseArtistId(JsonNode artistCredit) {
        if (artistCredit == null || !artistCredit.isArray() || artistCredit.isEmpty()) {
            return null;
        }
        JsonNode first = artistCredit.get(0);
        JsonNode artist = first == null ? null : first.path("artist");
        return artist == null || !artist.isObject() ? null : text(artist, "id");
    }

    private String artistCreditName(JsonNode artistCredit) {
        if (artistCredit == null || !artistCredit.isArray() || artistCredit.isEmpty()) {
            return "";
        }
        List<String> names = new ArrayList<>();
        for (int index = 0; index < artistCredit.size(); index++) {
            JsonNode credit = artistCredit.get(index);
            if (credit == null || !credit.isObject()) {
                continue;
            }
            String name = text(credit, "name");
            if (!name.isBlank()) {
                names.add(name);
            }
        }
        return String.join(", ", names);
    }

    private String trimTrailingSlash(String value) {
        if (value == null || value.isBlank()) {
            return "";
        }
        return value.endsWith("/") ? value.substring(0, value.length() - 1) : value;
    }

    private String url(String value) {
        return URLEncoder.encode(value == null ? "" : value, StandardCharsets.UTF_8);
    }

    private record ReleaseSearchResult(
            String id,
            String title,
            String artistName,
            LocalDate releaseDate,
            int score,
            String releaseGroupId,
            String artistId
    ) {
    }

    private record ReleaseDetail(
            String releaseId,
            String title,
            String releaseGroupId,
            String artistId,
            String artistName,
            LocalDate releaseDate,
            List<ReleaseTrack> tracks,
            String genre
    ) {
    }

    private record ReleaseTrack(
            String recordingId,
            String title,
            Integer trackNumber,
            Integer discNumber,
            Integer durationSeconds
    ) {
    }

    private record TrackMatch(
            String recordingId,
            String title,
            Integer trackNumber,
            Integer discNumber,
            Integer durationSeconds,
            int score,
            List<String> reasons
    ) {
    }
}
