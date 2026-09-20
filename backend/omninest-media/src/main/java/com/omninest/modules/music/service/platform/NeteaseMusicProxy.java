package com.omninest.modules.music.service.platform;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.music.dto.OnlineMusicDtos.OnlinePlaylistDto;
import com.omninest.modules.music.dto.OnlineMusicDtos.OnlineTrackDto;
import com.omninest.modules.music.dto.OnlineMusicDtos.PlaybackUrlResult;
import com.omninest.modules.music.dto.OnlineMusicDtos.PlatformUserInfo;
import com.omninest.modules.music.dto.OnlineMusicDtos.QrLoginSession;
import com.omninest.modules.music.dto.OnlineMusicDtos.QrLoginStatus;
import com.omninest.modules.music.service.MusicPlatformCredentialService;
import com.omninest.modules.music.service.MusicRuntimeConfigService;
import java.io.IOException;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

/**
 * 网易云音乐平台代理实现。
 * 通过 HTTP 调用本地 Docker 容器（NeteaseCloudMusicApi）提供在线音乐服务。
 * 容器内部处理 weapi 加密，Java 端仅负责 HTTP 通信和数据解析。
 *
 * @author OmniNest
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class NeteaseMusicProxy implements MusicPlatformProvider {

    private static final Duration REQUEST_TIMEOUT = Duration.ofSeconds(10);
    private static final int MAX_ACCOUNT_TRACKS = 1_000;
    private static final int SONG_DETAIL_CHUNK_SIZE = 500;
    private static final String USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
            + "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";
    private static final List<String> ACCOUNT_PROFILE_PATHS = List.of(
            "/user/account?timestamp=",
            "/login/status?timestamp="
    );
    private static final Set<String> COOKIE_ATTRIBUTE_NAMES = Set.of(
            "domain",
            "expires",
            "httponly",
            "max-age",
            "partitioned",
            "path",
            "priority",
            "samesite",
            "secure"
    );

    /**
     * 音质等级列表，从高到低排列。
     * 播放时从最高音质开始探测，直到找到可用资源。
     */
    private static final List<String> QUALITY_LEVELS = List.of(
            "jymaster",
            "jyeffect",
            "sky",
            "dolby",
            "hires",
            "lossless",
            "exhigh",
            "higher",
            "standard"
    );

    private final MusicRuntimeConfigService configService;
    private final MusicPlatformCredentialService credentialService;

    private final HttpClient httpClient = HttpClient.newBuilder()
            .connectTimeout(REQUEST_TIMEOUT)
            .followRedirects(HttpClient.Redirect.NORMAL)
            .build();

    @Override
    public MusicPlatform platform() {
        return MusicPlatform.NETEASE;
    }

    @Override
    public MusicPlatformCapabilities capabilities() {
        return new MusicPlatformCapabilities(true, true, true, true, true, QUALITY_LEVELS);
    }

    @Override
    public List<OnlineTrackDto> search(UUID ownerUserId, String keyword, int limit) {
        if (!enabled()) {
            log.debug("网易云音乐平台未启用，跳过搜索");
            return List.of();
        }
        if (keyword == null || keyword.isBlank()) {
            return List.of();
        }
        try {
            String path = "/cloudsearch?keywords=" + encode(keyword)
                    + "&limit=" + limit
                    + "&timestamp=" + System.currentTimeMillis();
            JSONObject json = requestJson(path, cookie(ownerUserId));
            if (json == null) {
                return List.of();
            }
            JSONObject result = json.getJSONObject("result");
            if (result == null) {
                return List.of();
            }
            JSONArray songs = result.getJSONArray("songs");
            if (songs == null || songs.isEmpty()) {
                return List.of();
            }
            List<OnlineTrackDto> tracks = new ArrayList<>();
            for (int i = 0; i < songs.size(); i++) {
                JSONObject song = songs.getJSONObject(i);
                OnlineTrackDto track = parseSearchResult(song);
                if (track != null) {
                    tracks.add(track);
                }
            }
            log.info("网易云搜索完成: 结果数={}", tracks.size());
            return tracks;
        } catch (InterruptedException ex) {
            Thread.currentThread().interrupt();
            log.warn("网易云搜索请求被中断");
            return List.of();
        } catch (IOException | RuntimeException ex) {
            log.warn("网易云搜索异常: errorType={}", ex.getClass().getSimpleName());
            return List.of();
        }
    }

    @Override
    public PlaybackUrlResult getPlaybackUrl(UUID ownerUserId, String songId, String mediaMid, String quality) {
        if (!enabled()) {
            log.debug("网易云音乐平台未启用，跳过获取播放URL");
            return new PlaybackUrlResult(null, null, null, "平台未启用");
        }
        if (songId == null || songId.isBlank()) {
            return new PlaybackUrlResult(null, null, null, "歌曲ID为空");
        }
        try {
            // 从请求音质开始向下探测
            int startIndex = startIndexForQuality(quality);
            for (int i = startIndex; i < QUALITY_LEVELS.size(); i++) {
                String level = QUALITY_LEVELS.get(i);
                String path = "/song/url/v1?id=" + songId
                        + "&level=" + level
                        + "&timestamp=" + System.currentTimeMillis();
                JSONObject json = requestJson(path, cookie(ownerUserId));
                if (json == null) {
                    continue;
                }
                JSONArray data = json.getJSONArray("data");
                if (data == null || data.isEmpty()) {
                    continue;
                }
                JSONObject songData = data.getJSONObject(0);
                String url = songData.getString("url");
                if (url != null && !url.isBlank()) {
                    String format = songData.getString("type");
                    log.info("网易云播放URL获取成功: songId={}, quality={}, format={}", songId, level, format);
                    return new PlaybackUrlResult(url, level, format, null);
                }
            }
            log.info("网易云播放URL获取失败: songId={}, 所有音质均不可用", songId);
            return new PlaybackUrlResult(null, null, null, "所有音质均不可用，可能需要VIP");
        } catch (InterruptedException ex) {
            Thread.currentThread().interrupt();
            log.warn("网易云播放URL请求被中断: songId={}", songId);
            return new PlaybackUrlResult(null, null, null, "请求被中断");
        } catch (IOException | RuntimeException ex) {
            log.warn("网易云播放URL异常: songId={}, message={}", songId, ex.getMessage());
            return new PlaybackUrlResult(null, null, null, "请求异常: " + ex.getMessage());
        }
    }

    @Override
    public LyricsResult getLyrics(UUID ownerUserId, String songId) {
        if (!enabled()) {
            log.debug("网易云音乐平台未启用，跳过获取歌词");
            return new LyricsResult(null, null);
        }
        if (songId == null || songId.isBlank()) {
            return new LyricsResult(null, null);
        }
        try {
            String path = "/lyric?id=" + songId
                    + "&timestamp=" + System.currentTimeMillis();
            JSONObject json = requestJson(path, cookie(ownerUserId));
            if (json == null) {
                return new LyricsResult(null, null);
            }
            // 同步歌词（LRC 格式，带时间戳）
            JSONObject lrcObj = json.getJSONObject("lrc");
            String syncedLyrics = lrcObj != null ? lrcObj.getString("lyric") : null;
            // 翻译歌词（LRC 格式带时间戳，与同步歌词行对齐）
            JSONObject tlyricObj = json.getJSONObject("tlyric");
            String translatedLyrics = tlyricObj != null ? tlyricObj.getString("lyric") : null;
            log.info("网易云歌词获取完成: songId={}, hasLyrics={}", songId, syncedLyrics != null);
            return new LyricsResult(null, syncedLyrics, translatedLyrics);
        } catch (InterruptedException ex) {
            Thread.currentThread().interrupt();
            log.warn("网易云歌词请求被中断: songId={}", songId);
            return new LyricsResult(null, null);
        } catch (IOException | RuntimeException ex) {
            log.warn("网易云歌词异常: songId={}, message={}", songId, ex.getMessage());
            return new LyricsResult(null, null);
        }
    }

    @Override
    public boolean isLoggedIn(UUID ownerUserId) {
        return credentialService.find(ownerUserId, MusicPlatform.NETEASE).isPresent();
    }

    @Override
    public List<OnlinePlaylistDto> playlists(UUID ownerUserId) {
        MusicPlatformCredential credential = requireCredentialWithExternalUserId(ownerUserId);
        if (credential == null) {
            return List.of();
        }
        try {
            String path = "/user/playlist?uid=" + encode(credential.externalUserId())
                    + "&limit=100&offset=0&timestamp=" + System.currentTimeMillis();
            JSONObject json = requestJson(path, credential.cookie());
            JSONArray playlists = json == null ? null : json.getJSONArray("playlist");
            if (playlists == null || playlists.isEmpty()) {
                return List.of();
            }
            List<OnlinePlaylistDto> results = new ArrayList<>();
            for (int index = 0; index < playlists.size(); index++) {
                OnlinePlaylistDto playlist = parsePlaylist(playlists.getJSONObject(index));
                if (playlist != null) {
                    results.add(playlist);
                }
            }
            return results;
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            log.warn("网易云用户歌单请求被中断: userId={}", ownerUserId);
            return List.of();
        } catch (IOException | RuntimeException exception) {
            log.warn("网易云用户歌单请求失败: userId={}, message={}", ownerUserId, exception.getMessage());
            return List.of();
        }
    }

    @Override
    public List<OnlineTrackDto> playlistTracks(UUID ownerUserId, String playlistId) {
        if (playlistId == null || playlistId.isBlank()) {
            return List.of();
        }
        try {
            String path = "/playlist/track/all?id=" + encode(playlistId)
                    + "&limit=" + MAX_ACCOUNT_TRACKS
                    + "&offset=0&timestamp=" + System.currentTimeMillis();
            JSONObject json = requestJson(path, cookie(ownerUserId));
            return parseSongs(json == null ? null : json.getJSONArray("songs"));
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            log.warn("网易云歌单曲目请求被中断: userId={}", ownerUserId);
            return List.of();
        } catch (IOException | RuntimeException exception) {
            log.warn("网易云歌单曲目请求失败: userId={}, message={}", ownerUserId, exception.getMessage());
            return List.of();
        }
    }

    @Override
    public List<OnlineTrackDto> likedTracks(UUID ownerUserId) {
        MusicPlatformCredential credential = requireCredentialWithExternalUserId(ownerUserId);
        if (credential == null) {
            return List.of();
        }
        try {
            String path = "/likelist?uid=" + encode(credential.externalUserId())
                    + "&timestamp=" + System.currentTimeMillis();
            JSONObject json = requestJson(path, credential.cookie());
            JSONArray ids = json == null ? null : json.getJSONArray("ids");
            if (ids == null || ids.isEmpty()) {
                return List.of();
            }
            int total = Math.min(ids.size(), MAX_ACCOUNT_TRACKS);
            List<OnlineTrackDto> results = new ArrayList<>();
            for (int start = 0; start < total; start += SONG_DETAIL_CHUNK_SIZE) {
                int end = Math.min(start + SONG_DETAIL_CHUNK_SIZE, total);
                List<String> songIds = new ArrayList<>();
                for (int index = start; index < end; index++) {
                    songIds.add(ids.getString(index));
                }
                String detailPath = "/song/detail?ids=" + encode(String.join(",", songIds))
                        + "&timestamp=" + System.currentTimeMillis();
                JSONObject detail = requestJson(detailPath, credential.cookie());
                results.addAll(parseSongs(detail == null ? null : detail.getJSONArray("songs")));
            }
            return results;
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            log.warn("网易云喜欢歌曲请求被中断: userId={}", ownerUserId);
            return List.of();
        } catch (IOException | RuntimeException exception) {
            log.warn("网易云喜欢歌曲请求失败: userId={}, message={}", ownerUserId, exception.getMessage());
            return List.of();
        }
    }

    @Override
    public List<OnlineTrackDto> dailyRecommendedTracks(UUID ownerUserId) {
        MusicPlatformCredential credential = credential(ownerUserId);
        if (credential == null || credential.cookie().isBlank()) {
            throw new BusinessException(
                    ErrorCode.MUSIC_PLATFORM_NOT_CONNECTED,
                    "请先连接网易云音乐"
            );
        }
        try {
            JSONObject json = requestJson(
                    "/recommend/songs?timestamp=" + System.currentTimeMillis(),
                    credential.cookie()
            );
            if (json == null) {
                throw recommendationUnavailable();
            }
            int code = json.getIntValue("code");
            if (code == 301) {
                handleExpiredCredential(ownerUserId, credential.cookie());
            }
            if (code != 200) {
                log.warn("网易云每日推荐返回业务错误: userId={}, code={}", ownerUserId, code);
                throw recommendationUnavailable();
            }
            return parseDailyRecommendedTracks(json);
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            throw recommendationUnavailable();
        } catch (BusinessException exception) {
            throw exception;
        } catch (IOException | RuntimeException exception) {
            log.warn("网易云每日推荐请求失败: userId={}, message={}", ownerUserId, exception.getMessage());
            throw recommendationUnavailable();
        }
    }

    @Override
    public PlatformUserInfo getUserInfo(UUID ownerUserId) {
        MusicPlatformCredential credential = credential(ownerUserId);
        if (credential == null) {
            return emptyUserInfo();
        }
        PlatformUserInfo current = credential.userInfo();
        if (current.userId() != null && !current.userId().isBlank()) {
            return current;
        }
        PlatformUserInfo refreshed = fetchUserInfo(credential.cookie());
        if (refreshed.userId() == null || refreshed.userId().isBlank()) {
            return current;
        }
        credentialService.save(ownerUserId, MusicPlatform.NETEASE, credential.cookie(), refreshed);
        return refreshed;
    }

    @Override
    public void clearLogin(UUID ownerUserId) {
        credentialService.clear(ownerUserId, MusicPlatform.NETEASE);
        log.info("网易云登录状态已清除: userId={}", ownerUserId);
    }

    /**
     * 创建 QR 登录会话，返回二维码图片和登录密钥。
     *
     * @return QR 登录会话信息
     */
    public QrLoginSession createQrLogin() {
        try {
            // 步骤1：获取 unikey
            String keyPath = "/login/qr/key?timestamp=" + System.currentTimeMillis();
            JSONObject keyJson = requestJson(keyPath, null);
            if (keyJson == null) {
                log.warn("网易云QR登录：获取unikey失败");
                return null;
            }
            JSONObject keyData = keyJson.getJSONObject("data");
            if (keyData == null) {
                log.warn("网易云QR登录：unikey数据为空");
                return null;
            }
            String unikey = keyData.getString("unikey");
            if (unikey == null || unikey.isBlank()) {
                log.warn("网易云QR登录：unikey为空");
                return null;
            }

            // 步骤2：生成二维码
            String createPath = "/login/qr/create?key=" + encode(unikey)
                    + "&qrimg=true&timestamp=" + System.currentTimeMillis();
            JSONObject createJson = requestJson(createPath, null);
            if (createJson == null) {
                log.warn("网易云QR登录：生成二维码失败");
                return null;
            }
            JSONObject createData = createJson.getJSONObject("data");
            if (createData == null) {
                log.warn("网易云QR登录：二维码数据为空");
                return null;
            }
            String qrUrl = createData.getString("qrurl");
            String qrImageBase64 = createData.getString("qrimg");

            log.info("网易云QR登录会话已创建: unikey={}", unikey);
            return new QrLoginSession(unikey, qrUrl, qrImageBase64);
        } catch (InterruptedException ex) {
            Thread.currentThread().interrupt();
            log.warn("网易云QR登录创建被中断");
            return null;
        } catch (IOException | RuntimeException ex) {
            log.warn("网易云QR登录创建异常: message={}", ex.getMessage());
            return null;
        }
    }

    /**
     * 检查 QR 登录状态。
     *
     * @param loginKey 登录密钥（unikey）
     * @return 登录状态
     */
    public QrLoginStatus checkQrLogin(UUID ownerUserId, String loginKey) {
        if (loginKey == null || loginKey.isBlank()) {
            return new QrLoginStatus("expired", null);
        }
        try {
            String path = "/login/qr/check?key=" + encode(loginKey)
                    + "&timestamp=" + System.currentTimeMillis();
            NeteaseApiResponse apiResponse = request(path, null);
            JSONObject json = apiResponse.body();
            if (json == null) {
                return new QrLoginStatus("pending", null);
            }
            int code = json.getIntValue("code", -1);
            String cookie = mergeCookieHeaders(
                    apiResponse.cookie(),
                    json.getString("cookie")
            );

            return switch (code) {
                case 801 -> new QrLoginStatus("pending", null);
                case 802 -> new QrLoginStatus("scanned", null);
                case 803 -> {
                    // 登录成功：先落盘 Cookie 并立即返回，资料拉取交给后续 getUserInfo，
                    // 避免扫码确认响应被串行外部资料接口拖慢 1~4 秒。
                    if (cookie == null || cookie.isBlank()) {
                        String retryPath = "/login/qr/check?key=" + encode(loginKey)
                                + "&noCookie=true&timestamp=" + System.currentTimeMillis();
                        NeteaseApiResponse retryResponse = request(retryPath, null);
                        cookie = mergeCookieHeaders(
                                retryResponse.cookie(),
                                retryResponse.body() == null ? null : retryResponse.body().getString("cookie")
                        );
                    }
                    if (cookie == null || cookie.isBlank()) {
                        log.warn("网易云QR登录确认后未返回Cookie: userId={}", ownerUserId);
                        yield new QrLoginStatus("expired", null);
                    }
                    PlatformUserInfo userInfo = fallbackUserInfo();
                    credentialService.save(ownerUserId, MusicPlatform.NETEASE, cookie, userInfo);
                    log.info("网易云QR登录成功: userId={}", ownerUserId);
                    yield new QrLoginStatus("confirmed", userInfo);
                }
                case 800 -> new QrLoginStatus("expired", null);
                default -> {
                    log.warn("网易云QR登录未知状态码: code={}", code);
                    yield new QrLoginStatus("pending", null);
                }
            };
        } catch (InterruptedException ex) {
            Thread.currentThread().interrupt();
            log.warn("网易云QR登录检查被中断");
            return new QrLoginStatus("pending", null);
        } catch (IOException | RuntimeException ex) {
            log.warn("网易云QR登录检查异常: message={}", ex.getMessage());
            return new QrLoginStatus("pending", null);
        }
    }

    /**
     * 获取当前登录用户信息。
     *
     * @return 用户信息
     */
    private PlatformUserInfo fetchUserInfo(String cookie) {
        for (String pathPrefix : ACCOUNT_PROFILE_PATHS) {
            try {
                JSONObject json = requestJson(pathPrefix + System.currentTimeMillis(), cookie);
                PlatformUserInfo userInfo = parseUserInfo(json);
                if (userInfo.userId() != null && !userInfo.userId().isBlank()) {
                    return userInfo;
                }
            } catch (InterruptedException ex) {
                Thread.currentThread().interrupt();
                log.warn("网易云获取用户信息被中断");
                return emptyUserInfo();
            } catch (IOException | RuntimeException ex) {
                log.warn(
                        "网易云获取用户信息请求失败: endpoint={}, message={}",
                        pathPrefix,
                        ex.getMessage()
                );
            }
        }
        return emptyUserInfo();
    }

    /**
     * 解析网易云账号资料，兼容账号接口与登录状态接口的响应层级。
     *
     * @param json 网易云接口响应
     * @return 平台账号资料
     */
    PlatformUserInfo parseUserInfo(JSONObject json) {
        if (json == null) {
            return emptyUserInfo();
        }
        JSONObject payload = json.getJSONObject("data");
        if (payload == null) {
            payload = json;
        }
        JSONObject profile = payload.getJSONObject("profile");
        JSONObject account = payload.getJSONObject("account");
        if (account == null && payload != json) {
            account = json.getJSONObject("account");
        }
        String userId = valueOrEmpty(profile == null ? null : profile.getString("userId"));
        String nickname = valueOrEmpty(profile == null ? null : profile.getString("nickname"));
        String avatarUrl = valueOrEmpty(profile == null ? null : profile.getString("avatarUrl"));
        if (userId.isBlank() && account != null) {
            userId = valueOrEmpty(account.getString("id"));
        }
        if (nickname.isBlank() && account != null) {
            nickname = valueOrEmpty(account.getString("userName"));
        }
        boolean vip = (account != null && account.getIntValue("vipType") > 0)
                || (profile != null && profile.getIntValue("vipType") > 0);
        return new PlatformUserInfo(
                MusicPlatform.NETEASE.apiValue(),
                userId,
                nickname,
                avatarUrl,
                vip
        );
    }

    /**
     * 检查平台是否启用。
     */
    private boolean enabled() {
        return configService.onlineEnabled() && configService.neteaseEnabled();
    }

    /**
     * 解析搜索结果为 DTO。
     */
    private OnlineTrackDto parseSearchResult(JSONObject song) {
        String songId = String.valueOf(song.getLongValue("id"));
        String title = song.getString("name");
        if (songId.isBlank() || title == null || title.isBlank()) {
            return null;
        }
        // 解析艺术家列表
        JSONArray artists = song.getJSONArray("ar");
        String artistName = "";
        if (artists != null && !artists.isEmpty()) {
            List<String> names = new ArrayList<>();
            for (int i = 0; i < artists.size(); i++) {
                String name = artists.getJSONObject(i).getString("name");
                if (name != null && !name.isBlank()) {
                    names.add(name);
                }
            }
            artistName = String.join(", ", names);
        }
        // 解析专辑信息
        JSONObject album = song.getJSONObject("al");
        String albumTitle = "";
        String coverUrl = null;
        if (album != null) {
            albumTitle = album.getString("name");
            coverUrl = album.getString("picUrl");
        }
        // 时长（毫秒转秒）
        Integer durationSeconds = null;
        long dt = song.getLongValue("dt");
        if (dt > 0) {
            durationSeconds = (int) (dt / 1000);
        }
        Map<String, Object> extra = new LinkedHashMap<>();
        extra.put("albumId", album != null ? album.getLongValue("id") : null);
        return new OnlineTrackDto(
                "netease",
                songId,
                title,
                artistName,
                albumTitle,
                coverUrl,
                durationSeconds,
                null,
                extra
        );
    }

    /**
     * 发送 HTTP GET 请求并解析 JSON 响应。
     *
     * @param path 请求路径（含查询参数）
     * @return JSON 响应，失败返回 null
     */
    private JSONObject requestJson(String path, String cookie) throws IOException, InterruptedException {
        return request(path, cookie).body();
    }

    private NeteaseApiResponse request(String path, String cookie) throws IOException, InterruptedException {
        String baseUrl = trimTrailingSlash(configService.neteaseBaseUrl());
        URI uri = URI.create(baseUrl + path);
        HttpRequest.Builder requestBuilder = HttpRequest.newBuilder(uri)
                .timeout(REQUEST_TIMEOUT)
                .header("Accept", "application/json")
                .header("Referer", "https://music.163.com/")
                .header("User-Agent", USER_AGENT)
                .GET();
        if (cookie != null && !cookie.isBlank()) {
            String normalizedCookie = normalizeCookieHeader(cookie);
            if (!normalizedCookie.isBlank()) {
                requestBuilder.header("Cookie", normalizedCookie);
            }
        }
        HttpResponse<String> response = httpClient.send(requestBuilder.build(),
                HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
        if (response.statusCode() < 200 || response.statusCode() >= 300) {
            log.warn("网易云API请求失败: status={}, uri={}", response.statusCode(), uri);
            return new NeteaseApiResponse(null, "");
        }
        return new NeteaseApiResponse(
                JSONObject.parseObject(response.body()),
                responseCookie(response)
        );
    }

    private String responseCookie(HttpResponse<String> response) {
        Map<String, String> cookies = new LinkedHashMap<>();
        for (String setCookie : response.headers().allValues("Set-Cookie")) {
            int separator = setCookie.indexOf(';');
            String pair = separator < 0 ? setCookie : setCookie.substring(0, separator);
            putCookiePair(cookies, pair);
        }
        return String.join("; ", cookies.values());
    }

    String normalizeCookieHeader(String rawCookie) {
        if (rawCookie == null || rawCookie.isBlank()) {
            return "";
        }
        Map<String, String> cookies = new LinkedHashMap<>();
        for (String segment : rawCookie.split(";")) {
            putCookiePair(cookies, segment);
        }
        return String.join("; ", cookies.values());
    }

    private String mergeCookieHeaders(String first, String second) {
        return normalizeCookieHeader(valueOrEmpty(first) + ";" + valueOrEmpty(second));
    }

    private void putCookiePair(Map<String, String> cookies, String rawPair) {
        String pair = rawPair == null ? "" : rawPair.trim();
        int separator = pair.indexOf('=');
        if (separator <= 0 || separator == pair.length() - 1) {
            return;
        }
        String name = pair.substring(0, separator).trim();
        if (COOKIE_ATTRIBUTE_NAMES.contains(name.toLowerCase(Locale.ROOT))) {
            return;
        }
        String value = pair.substring(separator + 1).trim();
        cookies.put(name, name + "=" + value);
    }

    OnlinePlaylistDto parsePlaylist(JSONObject playlist) {
        if (playlist == null) {
            return null;
        }
        String playlistId = playlist.getString("id");
        String name = playlist.getString("name");
        if (playlistId == null || playlistId.isBlank() || name == null || name.isBlank()) {
            return null;
        }
        JSONObject creator = playlist.getJSONObject("creator");
        Map<String, Object> extra = new LinkedHashMap<>();
        if (creator != null) {
            extra.put("creatorUserId", creator.getString("userId"));
        }
        return new OnlinePlaylistDto(
                MusicPlatform.NETEASE.apiValue(),
                playlistId,
                name,
                playlist.getString("description"),
                playlist.getString("coverImgUrl"),
                playlist.getInteger("trackCount"),
                creator == null ? null : creator.getString("nickname"),
                playlist.getBooleanValue("subscribed"),
                extra
        );
    }

    List<OnlineTrackDto> parseDailyRecommendedTracks(JSONObject payload) {
        JSONObject data = payload == null ? null : payload.getJSONObject("data");
        JSONArray songs = data == null ? null : data.getJSONArray("dailySongs");
        List<OnlineTrackDto> tracks = parseSongs(songs);
        List<OnlineTrackDto> deduplicated = new ArrayList<>();
        Set<String> seenSongIds = new HashSet<>();
        for (OnlineTrackDto track : tracks) {
            if (track.songId() != null && seenSongIds.add(track.songId())) {
                deduplicated.add(track);
            }
        }
        return List.copyOf(deduplicated);
    }

    private void handleExpiredCredential(
            UUID ownerUserId,
            String cookie
    ) throws IOException, InterruptedException {
        Boolean loginActive = verifyLoginStatus(cookie);
        if (Boolean.FALSE.equals(loginActive)) {
            credentialService.clear(ownerUserId, MusicPlatform.NETEASE);
            throw new BusinessException(
                    ErrorCode.MUSIC_PLATFORM_AUTH_EXPIRED,
                    "网易云登录已失效，请重新连接"
            );
        }
        throw recommendationUnavailable();
    }

    private Boolean verifyLoginStatus(String cookie) throws IOException, InterruptedException {
        JSONObject status = requestJson(
                "/login/status?timestamp=" + System.currentTimeMillis(),
                cookie
        );
        if (status == null) {
            return null;
        }
        JSONObject data = status.getJSONObject("data");
        if (data == null) {
            return false;
        }
        return data.getJSONObject("account") != null || data.getJSONObject("profile") != null;
    }

    private BusinessException recommendationUnavailable() {
        return new BusinessException(
                ErrorCode.MUSIC_RECOMMENDATION_UNAVAILABLE,
                "网易云每日推荐暂不可用，请稍后重试"
        );
    }

    List<OnlineTrackDto> parseSongs(JSONArray songs) {
        if (songs == null || songs.isEmpty()) {
            return List.of();
        }
        List<OnlineTrackDto> results = new ArrayList<>();
        for (int index = 0; index < songs.size(); index++) {
            OnlineTrackDto track = parseSearchResult(songs.getJSONObject(index));
            if (track != null) {
                results.add(track);
            }
        }
        return results;
    }

    private String cookie(UUID ownerUserId) {
        MusicPlatformCredential credential = credential(ownerUserId);
        return credential == null ? null : credential.cookie();
    }

    private MusicPlatformCredential credential(UUID ownerUserId) {
        return credentialService.find(ownerUserId, MusicPlatform.NETEASE).orElse(null);
    }

    /**
     * 解析凭据中的外部用户 ID；为空时先回源补拉账号资料并重读凭据。
     *
     * <p>QR 确认会先以占位资料落盘，资料回源失败会留下空 externalUserId，
     * 此时歌单/喜欢接口静默返回空列表，前端表现为"已连接但全空"。
     * 返回 null 表示凭据不存在；补拉后仍无法确定账号则抛出明确错误码，
     * 由前端失败横幅呈现。</p>
     */
    private MusicPlatformCredential requireCredentialWithExternalUserId(UUID ownerUserId) {
        MusicPlatformCredential credential = credential(ownerUserId);
        if (credential == null) {
            return null;
        }
        if (credential.externalUserId() == null || credential.externalUserId().isBlank()) {
            getUserInfo(ownerUserId);
            credential = credential(ownerUserId);
            if (credential == null || credential.externalUserId() == null
                    || credential.externalUserId().isBlank()) {
                throw new BusinessException(
                        ErrorCode.MUSIC_PLATFORM_NOT_CONNECTED,
                        "网易云账号资料缺失，请重新登录"
                );
            }
        }
        return credential;
    }

    private PlatformUserInfo emptyUserInfo() {
        return new PlatformUserInfo(MusicPlatform.NETEASE.apiValue(), "", "", "", false);
    }

    private PlatformUserInfo fallbackUserInfo() {
        return new PlatformUserInfo(MusicPlatform.NETEASE.apiValue(), "", "网易云账号", "", false);
    }

    private String valueOrEmpty(String value) {
        return value == null ? "" : value;
    }

    private record NeteaseApiResponse(JSONObject body, String cookie) {
    }

    /**
     * 根据请求音质确定探测起始索引。
     */
    private int startIndexForQuality(String quality) {
        if (quality == null || quality.isBlank()) {
            return QUALITY_LEVELS.indexOf("exhigh");
        }
        String normalized = quality.trim().toLowerCase();
        for (int i = 0; i < QUALITY_LEVELS.size(); i++) {
            if (QUALITY_LEVELS.get(i).equals(normalized)) {
                return i;
            }
        }
        // 未识别的音质从最高开始探测
        return 0;
    }

    /**
     * 移除 URL 末尾的斜杠。
     */
    private String trimTrailingSlash(String value) {
        if (value == null || value.isBlank()) {
            return "";
        }
        return value.endsWith("/") ? value.substring(0, value.length() - 1) : value;
    }

    /**
     * URL 编码。
     */
    private String encode(String value) {
        return URLEncoder.encode(value == null ? "" : value, StandardCharsets.UTF_8);
    }
}
