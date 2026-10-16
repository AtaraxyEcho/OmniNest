package com.omninest.modules.video.service;

import com.omninest.common.json.JsonSupport;
import com.omninest.common.security.OutboundEndpointRules;
import com.omninest.common.security.SafeUrlValidator;
import com.omninest.modules.video.dto.MovieDtos.CastMemberDto;
import com.omninest.modules.video.dto.MovieDtos.CrewMemberDto;
import com.omninest.modules.video.dto.MovieDtos.ScrapeCandidateDto;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.LocalDate;
import java.time.format.DateTimeParseException;
import java.io.IOException;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;
import tools.jackson.databind.JsonNode;

@Slf4j
@Component
@RequiredArgsConstructor
public class TmdbMetadataProvider implements MetadataProvider {
    private static final int DEFAULT_MAX_RESULT_SIZE = 8;
    private static final String DEFAULT_BASE_URL = "https://api.themoviedb.org/3";
    private static final String SEARCH_STRATEGY_NORMALIZED_ONLY = "NORMALIZED_ONLY";
    private static final String SEARCH_STRATEGY_RAW_ONLY = "RAW_ONLY";
    private static final Duration CONNECT_TIMEOUT = Duration.ofSeconds(10);

    private final MediaRuntimeConfigService configService;
    private final SafeUrlValidator safeUrlValidator;

    /**
     * 共享的 HTTP 客户端。
     *
     * <p>原先每次请求 {@code HttpClient.newBuilder()} 新建一个，用完不关：JDK 的 HttpClient 自带
     * 选择器线程与连接池，刮削一轮下来会留下成倍泄漏的连接。连接超时因此不再跟随配置浮动
     * （要跟随就只能每次新建），请求级超时仍按 {@code tmdbTimeoutSeconds()} 生效。
     * 重定向策略固定为 NEVER：接口路径实测不产生跳转，一旦上游返回 3xx 说明目标已不在
     * 配置的基址内，交给调用方按请求失败处理，避免带着 API 凭据被带到别的主机。
     */
    private final HttpClient httpClient = HttpClient.newBuilder()
            .connectTimeout(CONNECT_TIMEOUT)
            .followRedirects(HttpClient.Redirect.NEVER)
            .build();

    @Override
    public String providerName() {
        return "TMDB";
    }

    @Override
    public List<ScrapeCandidateDto> search(FileNameGuess guess) {
        if (!enabled()) {
            log.debug("TMDB 提供器未启用，跳过搜索");
            return List.of();
        }
        TmdbCredential credential = credential();
        if (!credential.configured()) {
            log.debug("TMDB API Key / Access Token 未配置，跳过搜索");
            return List.of();
        }
        boolean tv = guess.seasonNumber() != null;
        log.info("TMDB 开始搜索: type={}", tv ? "TV" : "MOVIE");

        // 第一轮：按解析结果搜索（tv 或 movie）
        List<ScrapeCandidateDto> result = searchWithType(guess, credential, tv);
        if (!result.isEmpty()) {
            return result;
        }

        // 第二轮：回退到另一种类型搜索（主流媒体管理器的标准做法）
        boolean fallbackTv = !tv;
        log.info("TMDB 首轮搜索无结果，回退搜索: fallbackType={}", fallbackTv ? "TV" : "MOVIE");
        result = searchWithType(guess, credential, fallbackTv);
        if (!result.isEmpty()) {
            log.info("TMDB 回退搜索命中: type={}, candidates={}", fallbackTv ? "TV" : "MOVIE", result.size());
        }
        return result;
    }

    private List<ScrapeCandidateDto> searchWithType(
            FileNameGuess guess, TmdbCredential credential, boolean tv
    ) {
        for (String query : searchQueries(guess.title())) {
            log.debug("TMDB 查询: type={}, includeYear=true", tv ? "TV" : "MOVIE");
            List<ScrapeCandidateDto> candidates = requestCandidates(guess, credential, query, true, tv);
            if (!candidates.isEmpty()) {
                candidates = enrichDetail(candidates, credential, tv);
                log.info("TMDB 搜索命中: type={}, candidates={}", tv ? "TV" : "MOVIE", candidates.size());
                return candidates;
            }
            if (guess.year() != null) {
                log.debug("TMDB 查询: type={}, includeYear=false", tv ? "TV" : "MOVIE");
                candidates = requestCandidates(guess, credential, query, false, tv);
                if (!candidates.isEmpty()) {
                    candidates = enrichDetail(candidates, credential, tv);
                }
                log.info("TMDB 搜索命中(无年份过滤): type={}, candidates={}",
                        tv ? "TV" : "MOVIE", candidates.size());
                if (!candidates.isEmpty()) {
                    return candidates;
                }
            }
        }
        return List.of();
    }

    private boolean enabled() {
        return configService.metadataProvidersEnabled() && configService.tmdbEnabled();
    }

    private List<ScrapeCandidateDto> requestCandidates(
            FileNameGuess guess,
            TmdbCredential credential,
            String queryText,
            boolean includeYear,
            boolean tv
    ) {
        try {
            URI uri = searchUri(guess, credential, queryText, includeYear, tv);
            HttpRequest request = requestBuilder(uri, credential).GET().build();
            HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
            if (response.statusCode() < 200 || response.statusCode() >= 300) {
                log.warn("TMDB 请求失败: status={}, type={}",
                        response.statusCode(), tv ? "TV" : "MOVIE");
                return List.of();
            }
            String body = response.body();
            log.info("TMDB API 返回: type={}, status={}, bodyLength={}",
                    tv ? "TV" : "MOVIE", response.statusCode(), body.length());
            return parseCandidates(body, tv);
        } catch (InterruptedException ex) {
            Thread.currentThread().interrupt();
            log.warn("TMDB 请求被中断");
            return List.of();
        } catch (RuntimeException | IOException ex) {
            log.warn("TMDB 请求异常: errorType={}", ex.getClass().getSimpleName(), ex);
            return List.of();
        }
    }

    private URI searchUri(FileNameGuess guess, TmdbCredential credential, String queryText, boolean includeYear, boolean tv) {
        String path = tv ? "/search/tv" : "/search/movie";
        StringBuilder query = new StringBuilder();
        if (!credential.useBearer()) {
            query.append("api_key=").append(url(credential.apiKey())).append("&");
        }
        query.append("query=").append(url(queryText))
                .append("&language=").append(url(language()))
                .append("&include_adult=").append(configService.tmdbIncludeAdult())
                .append("&page=1");
        if (includeYear && guess.year() != null) {
            query.append(tv ? "&first_air_date_year=" : "&primary_release_year=").append(guess.year());
        }
        return apiUri(path, query);
    }

    /** 清除中文/西方季集标记的正则 */
    private static final Pattern CLEAN_SEASON_EPISODE = Pattern.compile(
            "(?:第[一二三四五六七八九十百\\d]+[季部][\\s.\\-_]?[Ee]?[Pp]?\\d{0,3})"
            + "|(?:第\\d{1,3}[集话話回])"
            + "|(?i)[Ss]\\d{1,2}[ ._-]?[Ee]\\d{1,2}"
            + "|(?:[Ee][Pp]?\\.?\\d{1,3})"
            + "|(?:\\s[-_ ]\\d{1,3}\\s*$)");

    private Set<String> searchQueries(String title) {
        LinkedHashSet<String> queries = new LinkedHashSet<>();
        String strategy = configService.tmdbSearchQueriesStrategy().trim().toUpperCase(Locale.ROOT);
        if (SEARCH_STRATEGY_RAW_ONLY.equals(strategy)) {
            String raw = title == null ? "" : title.trim();
            if (!raw.isBlank()) {
                queries.add(raw);
            }
            return queries;
        }
        String normalized = normalizeTitle(title);
        if (!normalized.isBlank()) {
            queries.add(normalized);
        }
        if (SEARCH_STRATEGY_NORMALIZED_ONLY.equals(strategy)) {
            return queries;
        }
        // 清除季集标记，提取干净的作品名
        String cleaned = CLEAN_SEASON_EPISODE.matcher(normalized).replaceAll(" ")
                .replaceAll("[._-]+", " ").replaceAll("\\s+", " ").trim();
        if (!cleaned.isBlank() && !cleaned.equals(normalized)) {
            queries.add(cleaned);
        }
        String withoutBrackets = normalized.replaceAll("[（(【\\[].*?[）)】\\]]", " ").replaceAll("\\s+", " ").trim();
        if (!withoutBrackets.isBlank() && !withoutBrackets.equals(normalized)) {
            queries.add(withoutBrackets);
        }
        return queries;
    }

    private String normalizeTitle(String title) {
        if (title == null) {
            return "";
        }
        return title.replaceAll("[._-]+", " ").replaceAll("\\s+", " ").trim();
    }

    private List<ScrapeCandidateDto> parseCandidates(String body, boolean tv) {
        JsonNode json = JsonSupport.readTree(body);
        JsonNode results = json.path("results");
        if (!results.isArray() || results.isEmpty()) {
            log.info("TMDB 解析结果为空: totalResults=0");
            return List.of();
        }
        int totalResults = json.path("total_results").asInt();
        log.info("TMDB 解析候选: totalResults={}, returnedResults={}, tv={}", totalResults, results.size(), tv);
        List<ScrapeCandidateDto> candidates = new ArrayList<>();
        int maxResults = maxResults();
        for (int index = 0; index < results.size() && candidates.size() < maxResults; index++) {
            JsonNode item = results.get(index);
            String title = text(item, tv ? "name" : "title");
            if (title.isBlank()) {
                continue;
            }
            String dateStr = text(item, tv ? "first_air_date" : "release_date");
            LocalDate releaseDate = parseDate(dateStr);
            candidates.add(new ScrapeCandidateDto(
                    providerName(),
                    String.valueOf(item.hasNonNull("id") ? item.path("id").asInt() : null),
                    title,
                    text(item, "original_title").isBlank() ? text(item, "original_name") : text(item, "original_title"),
                    releaseDate,
                    releaseDate != null ? releaseDate.getYear() : null,
                    text(item, "overview"),
                    posterUrl(text(item, "poster_path")),
                    backdropUrl(text(item, "backdrop_path")),
                    null,
                    item.hasNonNull("vote_average") ? item.path("vote_average").asDouble() : null,
                    null,
                    null, null, null, null, null, null, null, null, null, null, null
            ));
        }
        log.info("TMDB 候选列表: title={}, count={}, items={}",
                candidates.isEmpty() ? "(none)" : candidates.get(0).title(),
                candidates.size(),
                candidates.stream().map(ScrapeCandidateDto::title).toList());
        return candidates;
    }

    private List<ScrapeCandidateDto> enrichDetail(List<ScrapeCandidateDto> candidates, TmdbCredential credential, boolean tv) {
        if (candidates.isEmpty()) {
            return candidates;
        }
        ScrapeCandidateDto top = candidates.get(0);
        try {
            String path = tv ? "/tv/" + top.externalId() : "/movie/" + top.externalId();
            StringBuilder query = new StringBuilder();
            if (!credential.useBearer()) {
                query.append("api_key=").append(url(credential.apiKey())).append("&");
            }
            query.append("language=").append(url(language()));
            URI uri = apiUri(path, query);
            HttpRequest request = requestBuilder(uri, credential).GET().build();
            HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
            if (response.statusCode() >= 200 && response.statusCode() < 300) {
                String body = response.body();
                JsonNode detail = JsonSupport.readTree(body);
                log.info("TMDB 详情返回: externalId={}, bodyLength={}", top.externalId(), body.length());
                Integer runtime = null;
                if (tv) {
                    JsonNode episodeRunTime = detail.path("episode_run_time");
                    if (episodeRunTime.isArray() && !episodeRunTime.isEmpty()) {
                        runtime = episodeRunTime.hasNonNull(0) ? episodeRunTime.get(0).asInt() : null;
                    }
                } else {
                    runtime = detail.hasNonNull("runtime") ? detail.path("runtime").asInt() : null;
                }
                String imdbId = text(detail, "imdb_id");
                ImageFallback imageFallback = imageFallback(top, credential, tv);
                String posterUrl = posterUrl(text(detail, "poster_path"));
                String backdropUrl = backdropUrl(text(detail, "backdrop_path"));

                List<String> genres = extractGenreNames(detail.path("genres"));
                String tagline = detail.path("tagline").asString(null);
                Integer voteCount = detail.hasNonNull("vote_count") ? detail.path("vote_count").asInt() : null;
                Double popularity = detail.hasNonNull("popularity") ? detail.path("popularity").asDouble() : null;
                String originalLanguage = text(detail, "original_language");
                List<Map<String, Object>> studios = parseCompanyList(detail.path("production_companies"));
                List<Map<String, Object>> countries = parseCountryList(detail.path("production_countries"));
                List<CastMemberDto> cast = List.of();
                List<CrewMemberDto> crew = List.of();
                try {
                    var credits = fetchCredits(top.externalId(), credential, tv);
                    cast = credits.cast();
                    crew = credits.crew();
                } catch (Exception ex) {
                    log.warn("TMDB 演职员获取异常: externalId={}, message={}", top.externalId(), ex.getMessage());
                }
                String contentRating = fetchContentRating(top.externalId(), credential, tv);
                List<String> screenshotUrls = fetchScreenshots(top.externalId(), credential, tv);

                ScrapeCandidateDto enriched = new ScrapeCandidateDto(
                        top.provider(),
                        top.externalId(),
                        top.title(),
                        text(detail, tv ? "original_name" : "original_title"),
                        top.releaseDate(),
                        top.year(),
                        text(detail, "overview"),
                        posterUrl == null ? imageFallback.posterUrl() : posterUrl,
                        backdropUrl == null ? imageFallback.backdropUrl() : backdropUrl,
                        runtime,
                        detail.hasNonNull("vote_average") ? detail.path("vote_average").asDouble() : null,
                        imdbId.isBlank() ? null : imdbId,
                        genres, cast, crew, voteCount,
                        contentRating,
                        tagline == null || tagline.isBlank() ? null : tagline,
                        popularity, originalLanguage, studios, countries, screenshotUrls
                );
                List<ScrapeCandidateDto> enrichedList = new ArrayList<>();
                enrichedList.add(enriched);
                enrichedList.addAll(candidates.subList(1, candidates.size()));
                log.info("TMDB 详情补充完成: externalId={}, runtime={}, imdbId={}, genres={}, cast={}, crew={}, contentRating={}",
                        top.externalId(), runtime, imdbId, genres.size(), cast.size(), crew.size(), contentRating);
                return enrichedList;
            }
            log.warn("TMDB 详情请求失败: status={}, externalId={}", response.statusCode(), top.externalId());
        } catch (Exception ex) {
            log.warn("TMDB 详情获取异常: externalId={}, message={}", top.externalId(), ex.getMessage());
        }
        return candidates;
    }

    private record CreditsResult(List<CastMemberDto> cast, List<CrewMemberDto> crew) {}

    private CreditsResult fetchCredits(String externalId, TmdbCredential credential, boolean tv) {
        String path = tv ? "/tv/" + externalId + "/credits" : "/movie/" + externalId + "/credits";
        StringBuilder query = new StringBuilder();
        if (!credential.useBearer()) {
            query.append("api_key=").append(url(credential.apiKey())).append("&");
        }
        query.append("language=").append(url(language()));
        try {
            URI uri = apiUri(path, query);
            HttpRequest request = requestBuilder(uri, credential).GET().build();
            HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
            if (response.statusCode() < 200 || response.statusCode() >= 300) {
                log.warn("TMDB 演职员请求失败: status={}, externalId={}", response.statusCode(), externalId);
                return new CreditsResult(List.of(), List.of());
            }
            JsonNode json = JsonSupport.readTree(response.body());
            List<CastMemberDto> cast = new ArrayList<>();
            JsonNode castArray = json.path("cast");
            if (castArray.isArray()) {
                int limit = Math.min(castArray.size(), 20);
                for (int i = 0; i < limit; i++) {
                    JsonNode c = castArray.get(i);
                    cast.add(new CastMemberDto(
                            text(c, "name"),
                            text(c, "character"),
                            profileUrl(text(c, "profile_path")),
                            c.hasNonNull("order") ? c.path("order").asInt() : null
                    ));
                }
            }
            List<CrewMemberDto> crew = new ArrayList<>();
            JsonNode crewArray = json.path("crew");
            if (crewArray.isArray()) {
                int limit = Math.min(crewArray.size(), 20);
                for (int i = 0; i < limit; i++) {
                    JsonNode c = crewArray.get(i);
                    crew.add(new CrewMemberDto(
                            text(c, "name"),
                            text(c, "job"),
                            text(c, "department"),
                            profileUrl(text(c, "profile_path"))
                    ));
                }
            }
            log.info("TMDB 演职员获取完成: externalId={}, cast={}, crew={}", externalId, cast.size(), crew.size());
            return new CreditsResult(cast, crew);
        } catch (InterruptedException ex) {
            Thread.currentThread().interrupt();
            return new CreditsResult(List.of(), List.of());
        } catch (Exception ex) {
            log.warn("TMDB 演职员获取异常: externalId={}, message={}", externalId, ex.getMessage());
            return new CreditsResult(List.of(), List.of());
        }
    }

    private String fetchContentRating(String externalId, TmdbCredential credential, boolean tv) {
        String path = tv ? "/tv/" + externalId + "/content_ratings" : "/movie/" + externalId + "/release_dates";
        StringBuilder query = new StringBuilder();
        if (!credential.useBearer()) {
            query.append("api_key=").append(url(credential.apiKey())).append("&");
        }
        try {
            URI uri = apiUri(path, query);
            HttpRequest request = requestBuilder(uri, credential).GET().build();
            HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
            if (response.statusCode() < 200 || response.statusCode() >= 300) {
                return null;
            }
            JsonNode json = JsonSupport.readTree(response.body());
            if (tv) {
                JsonNode results = json.path("results");
                if (results.isArray()) {
                    for (int i = 0; i < results.size(); i++) {
                        JsonNode entry = results.get(i);
                        if ("US".equals(text(entry, "iso_3166_1"))) {
                            String rating = text(entry, "rating");
                            return rating.isBlank() ? null : rating;
                        }
                    }
                    if (!results.isEmpty()) {
                        String rating = text(results.get(0), "rating");
                        return rating.isBlank() ? null : rating;
                    }
                }
            } else {
                JsonNode results = json.path("results");
                if (results.isArray()) {
                    for (int i = 0; i < results.size(); i++) {
                        JsonNode entry = results.get(i);
                        if ("US".equals(text(entry, "iso_3166_1"))) {
                            JsonNode releaseDates = entry.path("release_dates");
                            if (releaseDates.isArray()) {
                                for (int j = 0; j < releaseDates.size(); j++) {
                                    String cert = text(releaseDates.get(j), "certification");
                                    if (!cert.isBlank()) {
                                        return cert;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } catch (InterruptedException ex) {
            Thread.currentThread().interrupt();
        } catch (Exception ex) {
            log.warn("TMDB 内容分级获取异常: externalId={}, message={}", externalId, ex.getMessage());
        }
        return null;
    }

    private List<String> extractGenreNames(JsonNode genres) {
        if (genres == null || !genres.isArray() || genres.isEmpty()) {
            return List.of();
        }
        List<String> names = new ArrayList<>();
        for (int i = 0; i < genres.size(); i++) {
            String name = genres.get(i).path("name").asString(null);
            if (name != null && !name.isBlank()) {
                names.add(name);
            }
        }
        return names;
    }

    private List<Map<String, Object>> parseCompanyList(JsonNode companies) {
        if (companies == null || !companies.isArray() || companies.isEmpty()) {
            return List.of();
        }
        List<Map<String, Object>> result = new ArrayList<>();
        for (int i = 0; i < companies.size(); i++) {
            JsonNode c = companies.get(i);
            Map<String, Object> map = new LinkedHashMap<>();
            map.put("id", c.hasNonNull("id") ? c.path("id").asInt() : null);
            map.put("name", text(c, "name"));
            map.put("origin_country", text(c, "origin_country"));
            result.add(map);
        }
        return result;
    }

    private List<Map<String, Object>> parseCountryList(JsonNode countries) {
        if (countries == null || !countries.isArray() || countries.isEmpty()) {
            return List.of();
        }
        List<Map<String, Object>> result = new ArrayList<>();
        for (int i = 0; i < countries.size(); i++) {
            JsonNode c = countries.get(i);
            Map<String, Object> map = new LinkedHashMap<>();
            map.put("iso_3166_1", text(c, "iso_3166_1"));
            map.put("name", text(c, "name"));
            result.add(map);
        }
        return result;
    }

    private String profileUrl(String path) {
        return imageUrl(path, "w185");
    }

    private ImageFallback imageFallback(ScrapeCandidateDto top, TmdbCredential credential, boolean tv) {
        if ((top.posterUrl() != null && !top.posterUrl().isBlank())
                && (top.backdropUrl() != null && !top.backdropUrl().isBlank())) {
            return new ImageFallback(top.posterUrl(), top.backdropUrl());
        }
        try {
            String path = tv ? "/tv/" + top.externalId() + "/images" : "/movie/" + top.externalId() + "/images";
            StringBuilder query = new StringBuilder();
            if (!credential.useBearer()) {
                query.append("api_key=").append(url(credential.apiKey())).append("&");
            }
            query.append("include_image_language=")
                    .append(url(imageLanguages()));
            URI uri = apiUri(path, query);
            HttpRequest request = requestBuilder(uri, credential).GET().build();
            HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
            if (response.statusCode() < 200 || response.statusCode() >= 300) {
                log.warn("TMDB 图片请求失败: status={}, externalId={}", response.statusCode(), top.externalId());
                return new ImageFallback(top.posterUrl(), top.backdropUrl());
            }
            JsonNode json = JsonSupport.readTree(response.body());
            String posterUrl = top.posterUrl() == null || top.posterUrl().isBlank()
                    ? posterUrl(firstImagePath(json.path("posters")))
                    : top.posterUrl();
            String backdropUrl = top.backdropUrl() == null || top.backdropUrl().isBlank()
                    ? backdropUrl(firstImagePath(json.path("backdrops")))
                    : top.backdropUrl();
            return new ImageFallback(posterUrl, backdropUrl);
        } catch (Exception ex) {
            log.warn("TMDB 图片兜底获取异常: externalId={}, message={}", top.externalId(), ex.getMessage());
            return new ImageFallback(top.posterUrl(), top.backdropUrl());
        }
    }

    private String firstImagePath(JsonNode images) {
        if (images == null || !images.isArray() || images.isEmpty()) {
            return null;
        }
        for (int index = 0; index < images.size(); index++) {
            String filePath = text(images.get(index), "file_path");
            if (!filePath.isBlank()) {
                return filePath;
            }
        }
        return null;
    }

    private String posterUrl(String path) {
        return imageUrl(path, "w500");
    }

    private String backdropUrl(String path) {
        return imageUrl(path, "w1280");
    }

    private String imageUrl(String path, String size) {
        if (path == null || path.isBlank()) {
            return null;
        }
        return "https://image.tmdb.org/t/p/" + size + path;
    }

    private LocalDate parseDate(String date) {
        if (date == null || date.length() < 10) {
            return null;
        }
        try {
            return LocalDate.parse(date.substring(0, 10));
        } catch (DateTimeParseException ex) {
            return null;
        }
    }

    private String text(JsonNode item, String key) {
        String value = item.path(key).asString(null);
        return value == null ? "" : value.trim();
    }

    private String url(String value) {
        return URLEncoder.encode(value == null ? "" : value, StandardCharsets.UTF_8);
    }

    private HttpRequest.Builder requestBuilder(URI uri, TmdbCredential credential) {
        HttpRequest.Builder builder = HttpRequest.newBuilder(uri)
                .timeout(requestTimeout())
                .header("Accept", "application/json");
        if (credential.useBearer()) {
            builder.header("Authorization", "Bearer " + credential.accessToken());
        }
        return builder;
    }

    private Duration requestTimeout() {
        int seconds = configService.tmdbTimeoutSeconds();
        if (seconds < 3) {
            seconds = 3;
        }
        if (seconds > 120) {
            seconds = 120;
        }
        return Duration.ofSeconds(seconds);
    }

    private String language() {
        String language = configService.tmdbLanguage().trim();
        return language.isBlank() ? "zh-CN" : language;
    }

    private String imageLanguages() {
        String language = language();
        String prefix = language.contains("-") ? language.substring(0, language.indexOf('-')) : language;
        LinkedHashSet<String> values = new LinkedHashSet<>();
        values.add(language);
        values.add(prefix);
        values.add("en");
        values.add("null");
        return String.join(",", values);
    }

    private int maxResults() {
        int value = configService.tmdbMaxResults();
        if (value < 1) {
            return 1;
        }
        return Math.min(value, 20);
    }

    private TmdbCredential credential() {
        return new TmdbCredential(
                configService.tmdbApiKey(),
                configService.tmdbAccessToken(),
                apiVersion()
        );
    }

    private int apiVersion() {
        return apiVersion(configService.tmdbBaseUrl());
    }

    private int apiVersion(String baseUrl) {
        String normalized = trimTrailingSlash(baseUrl);
        Matcher matcher = Pattern.compile("/(\\d+)(?:/|$)").matcher(normalized);
        int version = 3;
        while (matcher.find()) {
            version = Integer.parseInt(matcher.group(1));
        }
        return version;
    }

    private URI apiUri(String path, CharSequence query) {
        String base = normalizedApiBaseUrl(configService.tmdbBaseUrl());
        return OutboundEndpointRules.requireConfiguredEndpoint(base, URI.create(base + path + "?" + query),
                safeUrlValidator);
    }

    private String normalizedApiBaseUrl(String value) {
        String base = trimTrailingSlash(value);
        Matcher matcher = Pattern.compile("/(3|4)(?:/|$)").matcher(base);
        if (matcher.find()) {
            return base.substring(0, matcher.start() + 2);
        }
        return base + "/3";
    }

    private String safeUri(URI uri) {
        String text = uri.toString();
        return text.replaceAll("api_key=[^&]+", "api_key=***");
    }

    private String trimTrailingSlash(String value) {
        if (value == null || value.isBlank()) {
            return DEFAULT_BASE_URL;
        }
        return value.endsWith("/") ? value.substring(0, value.length() - 1) : value;
    }

    private record TmdbCredential(String apiKey, String accessToken, int apiVersion) {
        private boolean configured() {
            return (apiKey != null && !apiKey.isBlank()) || (accessToken != null && !accessToken.isBlank());
        }

        private boolean useBearer() {
            if (accessToken == null || accessToken.isBlank()) {
                return false;
            }
            return apiVersion >= 4 || apiKey == null || apiKey.isBlank();
        }
    }

    private record ImageFallback(String posterUrl, String backdropUrl) {
    }

    private static final int MAX_SCREENSHOTS = 12;

    private List<String> fetchScreenshots(String externalId, TmdbCredential credential, boolean tv) {
        try {
            String path = tv ? "/tv/" + externalId + "/images" : "/movie/" + externalId + "/images";
            StringBuilder query = new StringBuilder();
            if (!credential.useBearer()) {
                query.append("api_key=").append(url(credential.apiKey())).append("&");
            }
            query.append("include_image_language=")
                    .append(url(imageLanguages()));
            URI uri = apiUri(path, query);
            HttpRequest request = requestBuilder(uri, credential).GET().build();
            HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
            if (response.statusCode() < 200 || response.statusCode() >= 300) {
                log.warn("TMDB 剧照请求失败: status={}, externalId={}", response.statusCode(), externalId);
                return List.of();
            }
            JsonNode json = JsonSupport.readTree(response.body());
            JsonNode backdrops = json.path("backdrops");
            if (!backdrops.isArray() || backdrops.isEmpty()) {
                return List.of();
            }
            List<String> urls = new ArrayList<>();
            for (int i = 0; i < backdrops.size() && urls.size() < MAX_SCREENSHOTS; i++) {
                JsonNode img = backdrops.get(i);
                String filePath = text(img, "file_path");
                if (!filePath.isBlank()) {
                    urls.add(backdropUrl(filePath));
                }
            }
            log.info("TMDB 剧照获取完成: externalId={}, count={}", externalId, urls.size());
            return urls;
        } catch (InterruptedException ex) {
            Thread.currentThread().interrupt();
            return List.of();
        } catch (Exception ex) {
            log.warn("TMDB 剧照获取异常: externalId={}, message={}", externalId, ex.getMessage());
            return List.of();
        }
    }
}
