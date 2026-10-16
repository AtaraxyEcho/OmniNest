package com.omninest.modules.music.service.platform;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.json.JsonSupport;
import com.omninest.common.error.BusinessException;
import com.omninest.common.security.OutboundEndpointRules;
import com.omninest.common.security.SafeUrlValidator;
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
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionException;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;
import tools.jackson.databind.JsonNode;

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
    private static final String PARAM_SIZE_KEY = "paramSize";
    private static final String THUMBNAIL_SIZE = "300x300";
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
    private final SafeUrlValidator safeUrlValidator;

    private final HttpClient httpClient = HttpClient.newBuilder()
            .connectTimeout(REQUEST_TIMEOUT)
            .followRedirects(HttpClient.Redirect.NEVER)
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
            JsonNode json = requestJson(path, cookie(ownerUserId));
            if (json == null) {
                return List.of();
            }
            JsonNode result = json.path("result");
            if (!result.isObject()) {
                return List.of();
            }
            JsonNode songs = result.path("songs");
            if (!songs.isArray() || songs.isEmpty()) {
                return List.of();
            }
            List<OnlineTrackDto> tracks = new ArrayList<>();
            for (int i = 0; i < songs.size(); i++) {
                JsonNode song = songs.get(i);
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
                JsonNode json = requestJson(path, cookie(ownerUserId));
                if (json == null) {
                    continue;
                }
                JsonNode data = json.path("data");
                if (!data.isArray() || data.isEmpty()) {
                    continue;
                }
                JsonNode songData = data.get(0);
                String url = songData.path("url").asString(null);
                if (url != null && !url.isBlank()) {
                    String format = songData.path("type").asString(null);
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
            String cookie = cookie(ownerUserId);
            String path = "/lyric?id=" + songId
                    + "&timestamp=" + System.currentTimeMillis();
            JsonNode json = requestJson(path, cookie);
            if (json == null) {
                return new LyricsResult(null, null);
            }
            // 同步歌词（LRC 格式，带时间戳）
            JsonNode lrcObj = json.path("lrc");
            String syncedLyrics = lrcObj.isObject() ? lrcObj.path("lyric").asString(null) : null;
            // 翻译歌词（LRC 格式带时间戳，与同步歌词行对齐）
            JsonNode tlyricObj = json.path("tlyric");
            String translatedLyrics = tlyricObj.isObject() ? tlyricObj.path("lyric").asString(null) : null;
            // 逐字歌词来自附加接口，失败时降级为不可用，不影响行级歌词
            String wordLyrics = fetchWordLyrics(songId, cookie);
            log.info(
                    "网易云歌词获取完成: songId={}, hasLyrics={}, hasWordLyrics={}",
                    songId,
                    syncedLyrics != null,
                    wordLyrics != null
            );
            return new LyricsResult(null, syncedLyrics, translatedLyrics, wordLyrics);
        } catch (InterruptedException ex) {
            Thread.currentThread().interrupt();
            log.warn("网易云歌词请求被中断: songId={}", songId);
            return new LyricsResult(null, null);
        } catch (IOException | RuntimeException ex) {
            log.warn("网易云歌词异常: songId={}, message={}", songId, ex.getMessage());
            return new LyricsResult(null, null);
        }
    }

    /**
     * 通过附加接口 /lyric/new 获取逐字歌词（yrc）原始载荷。
     *
     * <p>该接口属附加能力：请求失败、响应非法或字段缺失时返回 null，
     * 不得抛出异常影响行级歌词结果。</p>
     *
     * @param songId 平台歌曲 ID
     * @param cookie 平台凭据 Cookie，可为 null
     * @return 逐字歌词（yrc.lyric），不可用时为 null
     */
    private String fetchWordLyrics(String songId, String cookie) {
        try {
            String path = "/lyric/new?id=" + songId
                    + "&timestamp=" + System.currentTimeMillis();
            JsonNode json = requestJson(path, cookie);
            if (json == null) {
                return null;
            }
            JsonNode yrcObj = json.path("yrc");
            return blankToNull(yrcObj.isObject() ? yrcObj.path("lyric").asString(null) : null);
        } catch (InterruptedException ex) {
            Thread.currentThread().interrupt();
            log.warn("网易云逐字歌词请求被中断: songId={}", songId);
            return null;
        } catch (IOException | RuntimeException ex) {
            log.warn("网易云逐字歌词请求失败: songId={}, message={}", songId, ex.getMessage());
            return null;
        }
    }

    /**
     * 空白字符串归一为 null，保持"null 表示不可用"的统一约定。
     *
     * @param value 原始字段值
     * @return 去掉首尾空白后非空的原始值，空白时为 null
     */
    private String blankToNull(String value) {
        return value == null || value.isBlank() ? null : value;
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
            JsonNode json = requestJson(path, credential.cookie());
            JsonNode playlists = json == null ? null : json.path("playlist");
            if (playlists == null || !playlists.isArray() || playlists.isEmpty()) {
                return List.of();
            }
            List<OnlinePlaylistDto> results = new ArrayList<>();
            for (int index = 0; index < playlists.size(); index++) {
                OnlinePlaylistDto playlist = parsePlaylist(playlists.get(index));
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
            JsonNode json = requestJson(path, cookie(ownerUserId));
            return parseSongs(json == null ? null : json.path("songs"));
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
            JsonNode json = requestJson(path, credential.cookie());
            JsonNode ids = json == null ? null : json.path("ids");
            if (ids == null || !ids.isArray() || ids.isEmpty()) {
                return List.of();
            }
            int total = Math.min(ids.size(), MAX_ACCOUNT_TRACKS);
            List<String> detailPaths = new ArrayList<>();
            for (int start = 0; start < total; start += SONG_DETAIL_CHUNK_SIZE) {
                int end = Math.min(start + SONG_DETAIL_CHUNK_SIZE, total);
                List<String> songIds = new ArrayList<>();
                for (int index = start; index < end; index++) {
                    songIds.add(ids.get(index).asString());
                }
                detailPaths.add("/song/detail?ids=" + encode(String.join(",", songIds))
                        + "&timestamp=" + System.currentTimeMillis());
            }
            // 曲目详情分块并行回源；聚合按 likelist 顺序拼接，保住默认播放序。
            // 任一分块传输异常按整支失败处理，与既有串行语义一致。
            List<CompletableFuture<NeteaseApiResponse>> details = detailPaths.stream()
                    .map(detailPath -> requestAsync(detailPath, credential.cookie()))
                    .toList();
            List<OnlineTrackDto> results = new ArrayList<>();
            for (CompletableFuture<NeteaseApiResponse> detail : details) {
                JsonNode payload = awaitResponse(detail).body();
                results.addAll(parseSongs(payload == null ? null : payload.path("songs")));
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
            JsonNode json = requestJson(
                    "/recommend/songs?timestamp=" + System.currentTimeMillis(),
                    credential.cookie()
            );
            if (json == null) {
                throw recommendationUnavailable();
            }
            int code = json.path("code").asInt();
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
            JsonNode keyJson = requestJson(keyPath, null);
            if (keyJson == null) {
                log.warn("网易云QR登录：获取unikey失败");
                return null;
            }
            JsonNode keyData = keyJson.path("data");
            if (!keyData.isObject()) {
                log.warn("网易云QR登录：unikey数据为空");
                return null;
            }
            String unikey = keyData.path("unikey").asString(null);
            if (unikey == null || unikey.isBlank()) {
                log.warn("网易云QR登录：unikey为空");
                return null;
            }

            // 步骤2：生成二维码
            String createPath = "/login/qr/create?key=" + encode(unikey)
                    + "&qrimg=true&timestamp=" + System.currentTimeMillis();
            JsonNode createJson = requestJson(createPath, null);
            if (createJson == null) {
                log.warn("网易云QR登录：生成二维码失败");
                return null;
            }
            JsonNode createData = createJson.path("data");
            if (!createData.isObject()) {
                log.warn("网易云QR登录：二维码数据为空");
                return null;
            }
            String qrUrl = createData.path("qrurl").asString(null);
            String qrImageBase64 = createData.path("qrimg").asString(null);

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
            JsonNode json = apiResponse.body();
            if (json == null) {
                return new QrLoginStatus("pending", null);
            }
            int code = json.path("code").asInt(-1);
            String cookie = mergeCookieHeaders(
                    apiResponse.cookie(),
                    json.path("cookie").asString(null)
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
                                retryResponse.body() == null ? null : retryResponse.body().path("cookie").asString(null)
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
                JsonNode json = requestJson(pathPrefix + System.currentTimeMillis(), cookie);
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
    PlatformUserInfo parseUserInfo(JsonNode json) {
        if (json == null) {
            return emptyUserInfo();
        }
        JsonNode payload = json.path("data");
        if (!payload.isObject()) {
            payload = json;
        }
        JsonNode profile = payload.path("profile");
        JsonNode account = payload.path("account");
        if (!account.isObject() && payload != json) {
            account = json.path("account");
        }
        boolean profilePresent = profile.isObject();
        boolean accountPresent = account.isObject();
        String userId = valueOrEmpty(profilePresent ? profile.path("userId").asString(null) : null);
        String nickname = valueOrEmpty(profilePresent ? profile.path("nickname").asString(null) : null);
        String avatarUrl = valueOrEmpty(profilePresent ? profile.path("avatarUrl").asString(null) : null);
        if (userId.isBlank() && accountPresent) {
            userId = valueOrEmpty(account.path("id").asString(null));
        }
        if (nickname.isBlank() && accountPresent) {
            nickname = valueOrEmpty(account.path("userName").asString(null));
        }
        boolean vip = (accountPresent && account.path("vipType").asInt() > 0)
                || (profilePresent && profile.path("vipType").asInt() > 0);
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
    private OnlineTrackDto parseSearchResult(JsonNode song) {
        String songId = String.valueOf(song.path("id").asLong());
        String title = song.path("name").asString(null);
        if (songId.isBlank() || title == null || title.isBlank()) {
            return null;
        }
        // 解析艺术家列表
        JsonNode artists = song.path("ar");
        String artistName = "";
        if (artists.isArray() && !artists.isEmpty()) {
            List<String> names = new ArrayList<>();
            for (int i = 0; i < artists.size(); i++) {
                String name = artists.get(i).path("name").asString(null);
                if (name != null && !name.isBlank()) {
                    names.add(name);
                }
            }
            artistName = String.join(", ", names);
        }
        // 解析专辑信息
        JsonNode album = song.path("al");
        String albumTitle = "";
        String coverUrl = null;
        if (album.isObject()) {
            albumTitle = album.path("name").asString(null);
            coverUrl = album.path("picUrl").asString(null);
        }
        // 时长（毫秒转秒）
        Integer durationSeconds = null;
        long dt = song.path("dt").asLong();
        if (dt > 0) {
            durationSeconds = (int) (dt / 1000);
        }
        Map<String, Object> extra = new LinkedHashMap<>();
        extra.put("albumId", album.isObject() ? album.path("id").asLong() : null);
        return new OnlineTrackDto(
                "netease",
                songId,
                title,
                artistName,
                albumTitle,
                coverUrl,
                durationSeconds,
                null,
                extra,
                thumbnailUrl(coverUrl)
        );
    }

    /**
     * 发送 HTTP GET 请求并解析 JSON 响应。
     *
     * @param path 请求路径（含查询参数）
     * @return JSON 响应，失败返回 null
     */
    private JsonNode requestJson(String path, String cookie) throws IOException, InterruptedException {
        return request(path, cookie).body();
    }

    private NeteaseApiResponse request(String path, String cookie) throws IOException, InterruptedException {
        HttpRequest.Builder requestBuilder = HttpRequest.newBuilder(requestUri(path))
                .timeout(REQUEST_TIMEOUT)
                .header("Accept", "application/json")
                .header("Referer", "https://music.163.com/")
                .header("User-Agent", USER_AGENT)
                .GET();
        attachCookie(requestBuilder, cookie);
        return execute(requestBuilder.build());
    }

    private URI requestUri(String path) {
        String base = trimTrailingSlash(configService.neteaseBaseUrl());
        return OutboundEndpointRules.requireConfiguredEndpoint(base, URI.create(base + path), safeUrlValidator);
    }

    private void attachCookie(HttpRequest.Builder requestBuilder, String cookie) {
        if (cookie != null && !cookie.isBlank()) {
            String normalizedCookie = normalizeCookieHeader(cookie);
            if (!normalizedCookie.isBlank()) {
                requestBuilder.header("Cookie", normalizedCookie);
            }
        }
    }

    private NeteaseApiResponse execute(HttpRequest request) throws IOException, InterruptedException {
        HttpResponse<String> response = httpClient.send(
                request,
                HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8)
        );
        return toApiResponse(response);
    }

    /**
     * 发送异步 GET 请求并解析 JSON 响应，供互不依赖的分块回源并行执行。
     *
     * @param path 请求路径（含查询参数）
     * @param cookie 平台凭据 Cookie，可为 null
     * @return 完成后携带解析结果的 future
     */
    private CompletableFuture<NeteaseApiResponse> requestAsync(String path, String cookie) {
        HttpRequest.Builder requestBuilder = HttpRequest.newBuilder(requestUri(path))
                .timeout(REQUEST_TIMEOUT)
                .header("Accept", "application/json")
                .header("Referer", "https://music.163.com/")
                .header("User-Agent", USER_AGENT)
                .GET();
        attachCookie(requestBuilder, cookie);
        return httpClient
                .sendAsync(requestBuilder.build(), HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8))
                .thenApply(this::toApiResponse);
    }

    /**
     * 等待异步响应完成，并把包装异常还原为与同步路径一致的异常类型。
     *
     * @param response 异步响应 future
     * @return 响应结果
     */
    private NeteaseApiResponse awaitResponse(CompletableFuture<NeteaseApiResponse> response)
            throws IOException, InterruptedException {
        try {
            return response.join();
        } catch (CompletionException exception) {
            Throwable cause = exception.getCause();
            if (cause instanceof IOException ioException) {
                throw ioException;
            }
            if (cause instanceof InterruptedException interrupted) {
                throw interrupted;
            }
            throw exception;
        }
    }

    private NeteaseApiResponse toApiResponse(HttpResponse<String> response) {
        if (response.statusCode() < 200 || response.statusCode() >= 300) {
            log.warn("网易云API请求失败: status={}, uri={}", response.statusCode(), response.uri());
            return new NeteaseApiResponse(null, "");
        }
        String responseBody = response.body();
        return new NeteaseApiResponse(
                responseBody == null || responseBody.isBlank() ? null : JsonSupport.readTree(responseBody),
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

    /**
     * 网易云图片 CDN 通过 paramSize 提供缩放位图，列表缩略位因此不必下载原图。
     *
     * @param coverUrl 原始封面地址
     * @return 缩略图地址；地址为空或已带尺寸参数时原样返回
     */
    static String thumbnailUrl(String coverUrl) {
        if (coverUrl == null || coverUrl.isBlank() || coverUrl.contains(PARAM_SIZE_KEY)) {
            return coverUrl;
        }
        return coverUrl
                + (coverUrl.contains("?") ? "&" : "?")
                + PARAM_SIZE_KEY
                + "="
                + THUMBNAIL_SIZE;
    }

    OnlinePlaylistDto parsePlaylist(JsonNode playlist) {
        if (playlist == null) {
            return null;
        }
        String playlistId = playlist.path("id").asString(null);
        String name = playlist.path("name").asString(null);
        if (playlistId == null || playlistId.isBlank() || name == null || name.isBlank()) {
            return null;
        }
        JsonNode creator = playlist.path("creator");
        boolean creatorPresent = creator.isObject();
        Map<String, Object> extra = new LinkedHashMap<>();
        if (creatorPresent) {
            extra.put("creatorUserId", creator.path("userId").asString(null));
        }
        return new OnlinePlaylistDto(
                MusicPlatform.NETEASE.apiValue(),
                playlistId,
                name,
                playlist.path("description").asString(null),
                playlist.path("coverImgUrl").asString(null),
                playlist.hasNonNull("trackCount") ? playlist.path("trackCount").asInt() : null,
                creatorPresent ? creator.path("nickname").asString(null) : null,
                playlist.path("subscribed").asBoolean(),
                extra,
                thumbnailUrl(playlist.path("coverImgUrl").asString(null))
        );
    }

    List<OnlineTrackDto> parseDailyRecommendedTracks(JsonNode payload) {
        JsonNode data = payload == null ? null : payload.path("data");
        JsonNode songs = data == null ? null : data.path("dailySongs");
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
        JsonNode status = requestJson(
                "/login/status?timestamp=" + System.currentTimeMillis(),
                cookie
        );
        if (status == null) {
            return null;
        }
        JsonNode data = status.path("data");
        if (!data.isObject()) {
            return false;
        }
        return data.path("account").isObject() || data.path("profile").isObject();
    }

    private BusinessException recommendationUnavailable() {
        return new BusinessException(
                ErrorCode.MUSIC_RECOMMENDATION_UNAVAILABLE,
                "网易云每日推荐暂不可用，请稍后重试"
        );
    }

    List<OnlineTrackDto> parseSongs(JsonNode songs) {
        if (songs == null || !songs.isArray() || songs.isEmpty()) {
            return List.of();
        }
        List<OnlineTrackDto> results = new ArrayList<>();
        for (int index = 0; index < songs.size(); index++) {
            OnlineTrackDto track = parseSearchResult(songs.get(index));
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

    private record NeteaseApiResponse(JsonNode body, String cookie) {
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
