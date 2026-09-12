package com.omninest.modules.music.service.platform;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.music.dto.OnlineMusicDtos.OnlinePlaylistDto;
import com.omninest.modules.music.dto.OnlineMusicDtos.OnlineTrackDto;
import com.omninest.modules.music.dto.OnlineMusicDtos.PlaybackUrlResult;
import com.omninest.modules.music.dto.OnlineMusicDtos.PlatformUserInfo;
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
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

/**
 * QQ 音乐平台 API 实现。
 * 直接调用 QQ 音乐 Web API（无加密），提供在线音乐搜索、播放和歌词功能。
 * 播放授权依赖 Cookie 中的 qm_keyst 字段。
 *
 * @author OmniNest
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class QQMusicApi implements MusicPlatformProvider {

    private static final Duration REQUEST_TIMEOUT = Duration.ofSeconds(10);
    private static final int MAX_PLAYLIST_TRACKS = 1_000;

    /**
     * 音质文件名模板，从高到低排列。
     * 格式：前缀 + mediaMid + 扩展名
     */
    private static final List<QualityTemplate> QUALITY_TEMPLATES = List.of(
            new QualityTemplate("RS01", ".flac", "hires", "Hi-Res FLAC"),
            new QualityTemplate("F000", ".flac", "lossless", "无损 FLAC"),
            new QualityTemplate("M800", ".mp3", "exhigh", "320k MP3"),
            new QualityTemplate("M500", ".mp3", "higher", "128k MP3"),
            new QualityTemplate("C400", ".m4a", "standard", "AAC M4A")
    );

    /** uin 正则：从 Cookie 中提取纯数字 uin（去掉前缀 o 或 O）。 */
    private static final Pattern UIN_PATTERN = Pattern.compile("[oO]?(\\d+)");
    private final MusicRuntimeConfigService configService;
    private final MusicPlatformCredentialService credentialService;

    private final HttpClient httpClient = HttpClient.newBuilder()
            .connectTimeout(REQUEST_TIMEOUT)
            .followRedirects(HttpClient.Redirect.NORMAL)
            .build();

    @Override
    public MusicPlatform platform() {
        return MusicPlatform.QQ;
    }

    @Override
    public MusicPlatformCapabilities capabilities() {
        List<String> qualityLevels = QUALITY_TEMPLATES.stream()
                .map(QualityTemplate::quality)
                .toList();
        return new MusicPlatformCapabilities(true, true, false, true, false, qualityLevels);
    }

    @Override
    public List<OnlineTrackDto> search(UUID ownerUserId, String keyword, int limit) {
        if (!enabled()) {
            log.debug("QQ音乐平台未启用，跳过搜索");
            return List.of();
        }
        if (keyword == null || keyword.isBlank()) {
            return List.of();
        }
        try {
            MusicPlatformCredential credential = credential(ownerUserId);
            // 第一步：调用 smartbox 获取候选列表
            List<SongCandidate> candidates = searchCandidates(keyword, limit, credential.cookie());
            if (candidates.isEmpty()) {
                log.info("QQ音乐搜索无候选结果");
                return List.of();
            }
            // 第二步：逐个获取歌曲详情
            List<OnlineTrackDto> tracks = new ArrayList<>();
            for (SongCandidate candidate : candidates) {
                OnlineTrackDto track = fetchSongDetail(candidate, credential.cookie());
                if (track != null) {
                    tracks.add(track);
                }
            }
            log.info("QQ音乐搜索完成: 结果数={}", tracks.size());
            return tracks;
        } catch (InterruptedException ex) {
            Thread.currentThread().interrupt();
            log.warn("QQ音乐搜索请求被中断");
            return List.of();
        } catch (IOException | RuntimeException ex) {
            log.warn("QQ音乐搜索异常: errorType={}", ex.getClass().getSimpleName(), ex);
            return List.of();
        }
    }

    @Override
    public PlaybackUrlResult getPlaybackUrl(UUID ownerUserId, String songId, String mediaMid, String quality) {
        if (!enabled()) {
            log.debug("QQ音乐平台未启用，跳过获取播放URL");
            return new PlaybackUrlResult(null, null, null, "平台未启用");
        }
        if (mediaMid == null || mediaMid.isBlank()) {
            return new PlaybackUrlResult(null, null, null, "mediaMid为空");
        }
        try {
            MusicPlatformCredential credential = credential(ownerUserId);
            // 确定探测起始索引
            int startIndex = startIndexForQuality(quality);
            // 构建文件名候选列表（从请求音质向下兼容）
            List<String> filenames = new ArrayList<>();
            for (int i = startIndex; i < QUALITY_TEMPLATES.size(); i++) {
                QualityTemplate template = QUALITY_TEMPLATES.get(i);
                filenames.add(template.prefix + mediaMid + template.extension);
            }
            // 调用 CgiGetVkey 获取播放URL
            return requestPlaybackUrl(songId, mediaMid, filenames, credential);
        } catch (InterruptedException ex) {
            Thread.currentThread().interrupt();
            log.warn("QQ音乐播放URL请求被中断: songId={}", songId);
            return new PlaybackUrlResult(null, null, null, "请求被中断");
        } catch (IOException | RuntimeException ex) {
            log.warn("QQ音乐播放URL异常: songId={}, message={}", songId, ex.getMessage());
            return new PlaybackUrlResult(null, null, null, "请求异常: " + ex.getMessage());
        }
    }

    @Override
    public LyricsResult getLyrics(UUID ownerUserId, String songId) {
        if (!enabled()) {
            log.debug("QQ音乐平台未启用，跳过获取歌词");
            return new LyricsResult(null, null);
        }
        if (songId == null || songId.isBlank()) {
            return new LyricsResult(null, null);
        }
        try {
            MusicPlatformCredential credential = credential(ownerUserId);
            String cUrl = trimTrailingSlash(configService.qqMusicCUrl());
            String path = cUrl + "/lyric/fcgi-bin/fcg_query_lyric_new.fcg"
                    + "?songmid=" + encode(songId)
                    + "&format=json"
                    + "&nobase64=0";
            JSONObject json = requestJson(path, true, credential.cookie());
            if (json == null) {
                return new LyricsResult(null, null);
            }
            int code = json.getIntValue("code", -1);
            if (code != 0) {
                log.warn("QQ音乐歌词获取失败: songId={}, code={}", songId, code);
                return new LyricsResult(null, null);
            }
            // Base64 解码歌词：lyric 为 LRC 格式（带时间戳），trans 为翻译（LRC 格式带时间戳）
            String syncedLyrics = decodeBase64(json.getString("lyric"));
            String translatedLyrics = decodeBase64(json.getString("trans"));
            log.info("QQ音乐歌词获取完成: songId={}, hasLyrics={}", songId, syncedLyrics != null);
            return new LyricsResult(null, syncedLyrics, translatedLyrics);
        } catch (InterruptedException ex) {
            Thread.currentThread().interrupt();
            log.warn("QQ音乐歌词请求被中断: songId={}", songId);
            return new LyricsResult(null, null);
        } catch (IOException | RuntimeException ex) {
            log.warn("QQ音乐歌词异常: songId={}, message={}", songId, ex.getMessage());
            return new LyricsResult(null, null);
        }
    }

    @Override
    public boolean isLoggedIn(UUID ownerUserId) {
        return credentialService.find(ownerUserId, MusicPlatform.QQ).isPresent();
    }

    @Override
    public List<OnlinePlaylistDto> playlists(UUID ownerUserId) {
        MusicPlatformCredential credential = credential(ownerUserId);
        String uin = credential.externalUserId();
        if (uin == null || uin.isBlank()) {
            return List.of();
        }
        try {
            String cUrl = trimTrailingSlash(configService.qqMusicCUrl());
            String createdUrl = cUrl + "/rsc/fcgi-bin/fcg_user_created_diss.fcg"
                    + "?hostuin=" + encode(uin)
                    + "&sin=0&size=100&format=json";
            String subscribedUrl = cUrl + "/rsc/fcgi-bin/fcg_get_profile_order_asset.fcg"
                    + "?cid=205360956&userid=" + encode(uin)
                    + "&reqfrom=1&sin=0&ein=99&format=json";
            List<OnlinePlaylistDto> results = new ArrayList<>();
            results.addAll(parsePlaylists(requestJson(createdUrl, true, credential.cookie()), false));
            results.addAll(parsePlaylists(requestJson(subscribedUrl, true, credential.cookie()), true));
            return deduplicatePlaylists(results);
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            log.warn("QQ音乐用户歌单请求被中断: userId={}", ownerUserId);
            return List.of();
        } catch (IOException | RuntimeException exception) {
            log.warn("QQ音乐用户歌单请求失败: userId={}, message={}", ownerUserId, exception.getMessage());
            return List.of();
        }
    }

    @Override
    public List<OnlineTrackDto> playlistTracks(UUID ownerUserId, String playlistId) {
        if (playlistId == null || playlistId.isBlank()) {
            return List.of();
        }
        MusicPlatformCredential credential = credential(ownerUserId);
        try {
            String uUrl = trimTrailingSlash(configService.qqMusicUUrl());
            JSONObject request = new JSONObject();
            request.put("comm", buildComm());
            JSONObject playlistRequest = new JSONObject();
            playlistRequest.put("module", "music.srfDissInfo.aiDissInfo");
            playlistRequest.put("method", "uniform_get_Dissinfo");
            JSONObject params = new JSONObject();
            params.put("disstid", playlistId);
            params.put("song_begin", 0);
            params.put("song_num", MAX_PLAYLIST_TRACKS);
            params.put("userinfo", 1);
            params.put("tag", 1);
            playlistRequest.put("param", params);
            request.put("req_0", playlistRequest);
            JSONObject json = postJson(uUrl, request.toJSONString(), credential.cookie());
            JSONObject response = json == null ? null : json.getJSONObject("req_0");
            JSONObject data = response == null ? null : response.getJSONObject("data");
            return parsePlaylistTracks(data == null ? null : data.getJSONArray("songlist"));
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            log.warn("QQ音乐歌单曲目请求被中断: userId={}", ownerUserId);
            return List.of();
        } catch (IOException | RuntimeException exception) {
            log.warn("QQ音乐歌单曲目请求失败: userId={}, message={}", ownerUserId, exception.getMessage());
            return List.of();
        }
    }

    @Override
    public List<OnlineTrackDto> likedTracks(UUID ownerUserId) {
        return List.of();
    }

    @Override
    public PlatformUserInfo getUserInfo(UUID ownerUserId) {
        return credentialService.find(ownerUserId, MusicPlatform.QQ)
                .map(MusicPlatformCredential::userInfo)
                .orElseGet(this::emptyUserInfo);
    }

    @Override
    public void clearLogin(UUID ownerUserId) {
        credentialService.clear(ownerUserId, MusicPlatform.QQ);
        log.info("QQ音乐登录状态已清除: userId={}", ownerUserId);
    }

    /**
     * 应用 Cookie 并获取用户信息。
     * 验证 Cookie 中是否包含必要字段（uin 和播放授权字段）。
     *
     * @param ownerUserId 当前用户 ID
     * @param cookie 完整的 Cookie 字符串
     * @return 用户信息
     * @throws BusinessException Cookie 为空、格式无效或已失效时抛出
     */
    public PlatformUserInfo applyCookie(UUID ownerUserId, String cookie) {
        if (cookie == null || cookie.isBlank()) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "QQ音乐Cookie不能为空");
        }
        String uin = extractUin(cookie);
        if (uin == null) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "QQ音乐Cookie缺少uin字段");
        }
        boolean hasPlayAuth = cookie.contains("qm_keyst")
                || cookie.contains("qqmusic_key")
                || cookie.contains("music_key");
        if (!hasPlayAuth) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "QQ音乐Cookie缺少播放授权字段");
        }
        PlatformUserInfo userInfo = fetchUserInfo(cookie, uin);
        if (userInfo.nickname() == null || userInfo.nickname().isBlank()) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "QQ音乐Cookie无效或已过期");
        }
        credentialService.save(ownerUserId, MusicPlatform.QQ, cookie, userInfo);
        log.info("QQ音乐Cookie注入成功: userId={}, uin={}, nickname={}", ownerUserId, uin, userInfo.nickname());
        return userInfo;
    }

    /**
     * 获取当前登录用户信息。
     *
     * @return 用户信息
     */
    private PlatformUserInfo fetchUserInfo(String cookie, String uin) {
        try {
            String cUrl = trimTrailingSlash(configService.qqMusicCUrl());
            String path = cUrl + "/rsc/fcgi-bin/fcg_get_profile_homepage.fcg"
                    + "?cid=205360838"
                    + "&reqfrom=1"
                    + "&userid=" + encode(uin);
            JSONObject json = requestJson(path, true, cookie);
            if (json == null) {
                return new PlatformUserInfo("qq", uin, "", "", false);
            }
            JSONObject data = json.getJSONObject("data");
            if (data == null) {
                return new PlatformUserInfo("qq", uin, "", "", false);
            }
            JSONObject creator = data.getJSONObject("creator");
            if (creator == null) {
                return new PlatformUserInfo("qq", uin, "", "", false);
            }
            String nickname = creator.getString("nick");
            String avatarUrl = creator.getString("headpic");
            // VIP 状态判断
            JSONObject vip = data.getJSONObject("vip");
            boolean isVip = vip != null && vip.getIntValue("vip_flag") > 0;
            return new PlatformUserInfo("qq", uin, nickname, avatarUrl, isVip);
        } catch (InterruptedException ex) {
            Thread.currentThread().interrupt();
            log.warn("QQ音乐获取用户信息被中断");
            return new PlatformUserInfo("qq", uin, "", "", false);
        } catch (IOException | RuntimeException ex) {
            log.warn("QQ音乐获取用户信息异常: message={}", ex.getMessage());
            return new PlatformUserInfo("qq", uin, "", "", false);
        }
    }

    /**
     * 搜索候选列表（smartbox 接口）。
     */
    private List<SongCandidate> searchCandidates(String keyword, int limit, String cookie)
            throws IOException, InterruptedException {
        String cUrl = trimTrailingSlash(configService.qqMusicCUrl());
        String path = cUrl + "/splcloud/fcgi-bin/smartbox_new.fcg"
                + "?key=" + encode(keyword)
                + "&format=json";
        JSONObject json = requestJson(path, false, cookie);
        if (json == null) {
            return List.of();
        }
        JSONObject data = json.getJSONObject("data");
        if (data == null) {
            return List.of();
        }
        JSONObject song = data.getJSONObject("song");
        if (song == null) {
            return List.of();
        }
        JSONArray list = song.getJSONArray("list");
        if (list == null || list.isEmpty()) {
            return List.of();
        }
        List<SongCandidate> candidates = new ArrayList<>();
        int count = Math.min(list.size(), limit);
        for (int i = 0; i < count; i++) {
            JSONObject item = list.getJSONObject(i);
            String songMid = item.getString("songmid");
            String songName = item.getString("song");
            String singerName = item.getString("singer");
            if (songMid == null || songMid.isBlank()) {
                continue;
            }
            candidates.add(new SongCandidate(songMid, songName, singerName));
        }
        return candidates;
    }

    /**
     * 获取歌曲详情（music.pf_song_detail_svr.get_song_detail_yqq）。
     */
    private OnlineTrackDto fetchSongDetail(SongCandidate candidate, String cookie)
            throws IOException, InterruptedException {
        String uUrl = trimTrailingSlash(configService.qqMusicUUrl());
        // 构建请求体
        JSONObject req = new JSONObject();
        req.put("comm", buildComm());
        JSONObject songDetail = new JSONObject();
        songDetail.put("method", "get_song_detail_yqq");
        songDetail.put("module", "music.pf_song_detail_svr");
        JSONObject param = new JSONObject();
        param.put("song_mid", candidate.songMid());
        param.put("song_type", 0);
        songDetail.put("param", param);
        req.put("req_1", songDetail);
        JSONObject json = postJson(uUrl, req.toJSONString(), cookie);
        if (json == null) {
            return null;
        }
        JSONObject req1 = json.getJSONObject("req_1");
        if (req1 == null) {
            return null;
        }
        JSONObject detailData = req1.getJSONObject("data");
        if (detailData == null) {
            return null;
        }
        JSONObject trackInfo = detailData.getJSONObject("track_info");
        if (trackInfo == null) {
            return null;
        }
        return parseTrackInfo(trackInfo, candidate);
    }

    OnlineTrackDto parseTrackInfo(JSONObject trackInfo) {
        return parseTrackInfo(trackInfo, null);
    }

    private OnlineTrackDto parseTrackInfo(JSONObject trackInfo, SongCandidate candidate) {
        if (trackInfo == null) {
            return null;
        }
        String songId = firstText(trackInfo.getString("mid"), trackInfo.getString("songmid"));
        if ((songId == null || songId.isBlank()) && candidate != null) {
            songId = candidate.songMid();
        }
        String title = firstText(trackInfo.getString("name"), candidate == null ? null : candidate.songName());
        if (songId == null || songId.isBlank() || title == null || title.isBlank()) {
            return null;
        }
        String artistName = parseSingerNames(trackInfo.getJSONArray("singer"));
        if (artistName.isBlank() && candidate != null) {
            artistName = candidate.singerName();
        }
        String albumTitle = "";
        String coverUrl = null;
        JSONObject album = trackInfo.getJSONObject("album");
        if (album != null) {
            albumTitle = album.getString("name");
            // 封面 URL 模式：https://y.qq.com/music/photo_new/T002R300x300M000{albumMid}.jpg
            String albumMid = album.getString("mid");
            if (albumMid != null && !albumMid.isBlank()) {
                coverUrl = "https://y.qq.com/music/photo_new/T002R300x300M000" + albumMid + ".jpg";
            }
        }
        Integer durationSeconds = null;
        int interval = trackInfo.getIntValue("interval");
        if (interval > 0) {
            durationSeconds = interval;
        }
        // mediaMid 用于播放URL获取
        JSONObject fileObj = trackInfo.getJSONObject("file");
        String mediaMid = fileObj != null ? fileObj.getString("media_mid") : null;
        Map<String, Object> extra = new LinkedHashMap<>();
        extra.put("mediaMid", mediaMid);
        extra.put("albumMid", album != null ? album.getString("mid") : null);
        extra.put("numericSongId", trackInfo.getString("songid"));
        return new OnlineTrackDto(
                MusicPlatform.QQ.apiValue(),
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

    List<OnlinePlaylistDto> parsePlaylists(JSONObject json, boolean subscribed) {
        JSONObject data = json == null ? null : json.getJSONObject("data");
        if (data == null) {
            return List.of();
        }
        JSONArray playlists = data.getJSONArray("disslist");
        if (playlists == null) {
            playlists = data.getJSONArray("cdlist");
        }
        if (playlists == null || playlists.isEmpty()) {
            return List.of();
        }
        List<OnlinePlaylistDto> results = new ArrayList<>();
        for (int index = 0; index < playlists.size(); index++) {
            OnlinePlaylistDto playlist = parsePlaylist(playlists.getJSONObject(index), subscribed);
            if (playlist != null) {
                results.add(playlist);
            }
        }
        return results;
    }

    private OnlinePlaylistDto parsePlaylist(JSONObject playlist, boolean subscribed) {
        if (playlist == null) {
            return null;
        }
        String playlistId = firstText(
                playlist.getString("tid"),
                firstText(playlist.getString("dissid"), playlist.getString("dirid"))
        );
        String name = firstText(playlist.getString("diss_name"), playlist.getString("dissname"));
        if (playlistId == null || playlistId.isBlank() || name == null || name.isBlank()) {
            return null;
        }
        Map<String, Object> extra = new LinkedHashMap<>();
        extra.put("directoryId", playlist.getString("dirid"));
        return new OnlinePlaylistDto(
                MusicPlatform.QQ.apiValue(),
                playlistId,
                name,
                firstText(playlist.getString("desc"), playlist.getString("diss_desc")),
                firstText(playlist.getString("logo"), playlist.getString("picurl")),
                firstInteger(playlist, "song_cnt", "songnum"),
                firstText(playlist.getString("nick"), playlist.getString("creator")),
                subscribed,
                extra
        );
    }

    List<OnlineTrackDto> parsePlaylistTracks(JSONArray songs) {
        if (songs == null || songs.isEmpty()) {
            return List.of();
        }
        List<OnlineTrackDto> results = new ArrayList<>();
        for (int index = 0; index < songs.size(); index++) {
            JSONObject item = songs.getJSONObject(index);
            JSONObject trackInfo = item == null ? null : item.getJSONObject("track_info");
            if (trackInfo == null && item != null) {
                trackInfo = item.getJSONObject("songInfo");
            }
            if (trackInfo == null) {
                trackInfo = item;
            }
            OnlineTrackDto track = parseTrackInfo(trackInfo, null);
            if (track != null) {
                results.add(track);
            }
        }
        return results;
    }

    private List<OnlinePlaylistDto> deduplicatePlaylists(List<OnlinePlaylistDto> playlists) {
        Set<String> seen = new LinkedHashSet<>();
        List<OnlinePlaylistDto> results = new ArrayList<>();
        for (OnlinePlaylistDto playlist : playlists) {
            if (seen.add(playlist.playlistId())) {
                results.add(playlist);
            }
        }
        return results;
    }

    private String parseSingerNames(JSONArray singers) {
        if (singers == null || singers.isEmpty()) {
            return "";
        }
        List<String> names = new ArrayList<>();
        for (int index = 0; index < singers.size(); index++) {
            String name = singers.getJSONObject(index).getString("name");
            if (name != null && !name.isBlank()) {
                names.add(name);
            }
        }
        return String.join(", ", names);
    }

    private Integer firstInteger(JSONObject source, String firstKey, String secondKey) {
        Integer first = source.getInteger(firstKey);
        return first == null ? source.getInteger(secondKey) : first;
    }

    private String firstText(String first, String second) {
        return first == null || first.isBlank() ? second : first;
    }

    /**
     * 请求播放URL（vkey.GetVkeyServer.CgiGetVkey）。
     */
    private PlaybackUrlResult requestPlaybackUrl(
            String songId,
            String mediaMid,
            List<String> filenames,
            MusicPlatformCredential credential
    ) throws IOException, InterruptedException {
        String uUrl = trimTrailingSlash(configService.qqMusicUUrl());
        // 构建文件名数组
        JSONArray filenameArray = new JSONArray();
        for (String filename : filenames) {
            filenameArray.add(filename);
        }
        // 构建请求体
        JSONObject req = new JSONObject();
        req.put("comm", buildComm());
        JSONObject getVkey = new JSONObject();
        getVkey.put("method", "CgiGetVkey");
        getVkey.put("module", "vkey.GetVkeyServer");
        JSONObject param = new JSONObject();
        param.put("filename", filenameArray);
        param.put("guid", "10000");
        param.put("songmid", new JSONArray(List.of(songId != null ? songId : mediaMid)));
        param.put("songtype", new JSONArray(List.of(0)));
        String uin = credential.externalUserId();
        param.put("uin", uin == null || uin.isBlank() ? "0" : uin);
        param.put("loginflag", uin == null || uin.isBlank() ? 0 : 1);
        getVkey.put("param", param);
        req.put("req_0", getVkey);
        JSONObject json = postJson(uUrl, req.toJSONString(), credential.cookie());
        if (json == null) {
            return new PlaybackUrlResult(null, null, null, "请求失败");
        }
        JSONObject req0 = json.getJSONObject("req_0");
        if (req0 == null) {
            return new PlaybackUrlResult(null, null, null, "响应格式错误");
        }
        JSONObject data = req0.getJSONObject("data");
        if (data == null) {
            return new PlaybackUrlResult(null, null, null, "数据为空");
        }
        // 检查错误码
        int code = req0.getIntValue("code", 0);
        if (code == 104003) {
            log.warn("QQ音乐播放授权失败: 需要登录授权（error 104003）");
            return new PlaybackUrlResult(null, null, null, "需要登录授权，请重新登录");
        }
        if (code != 0) {
            log.warn("QQ音乐播放请求失败: code={}", code);
            return new PlaybackUrlResult(null, null, null, "请求失败: code=" + code);
        }
        // 拼接完整播放URL
        JSONArray sip = data.getJSONArray("sip");
        JSONArray midurlinfo = data.getJSONArray("midurlinfo");
        if (sip == null || sip.isEmpty() || midurlinfo == null || midurlinfo.isEmpty()) {
            return new PlaybackUrlResult(null, null, null, "播放URL数据缺失");
        }
        String baseUrl = sip.getString(0);
        JSONObject urlInfo = midurlinfo.getJSONObject(0);
        String purl = urlInfo.getString("purl");
        if (purl == null || purl.isBlank()) {
            log.warn("QQ音乐播放URL为空（可能需要VIP）: songId={}", songId);
            return new PlaybackUrlResult(null, null, null, "播放URL为空，可能需要VIP");
        }
        String fullUrl = baseUrl + purl;
        // 根据文件名判断格式和音质
        String format = guessFormat(purl);
        String detectedQuality = detectQuality(purl);
        log.info("QQ音乐播放URL获取成功: songId={}, quality={}, format={}", songId, detectedQuality, format);
        return new PlaybackUrlResult(fullUrl, detectedQuality, format, null);
    }

    /**
     * 检查平台是否启用。
     */
    private boolean enabled() {
        return configService.onlineEnabled() && configService.qqMusicEnabled();
    }

    /**
     * 构建公共请求参数。
     */
    private JSONObject buildComm() {
        JSONObject comm = new JSONObject();
        comm.put("g_tk", 5381);
        comm.put("format", "json");
        comm.put("inCharset", "utf-8");
        comm.put("outCharset", "utf-8");
        comm.put("notice", 0);
        comm.put("platform", "yqq.json");
        comm.put("needNewCode", 0);
        return comm;
    }

    /**
     * 发送 HTTP GET 请求并解析 JSON 响应。
     *
     * @param url       完整请求 URL
     * @param needCookie 是否注入 Cookie
     * @return JSON 响应，失败返回 null
     */
    private JSONObject requestJson(String url, boolean needCookie, String cookie)
            throws IOException, InterruptedException {
        HttpRequest.Builder requestBuilder = HttpRequest.newBuilder(URI.create(url))
                .timeout(REQUEST_TIMEOUT)
                .header("Accept", "application/json")
                .header("Referer", "https://y.qq.com/")
                .GET();
        if (needCookie && cookie != null && !cookie.isBlank()) {
            requestBuilder.header("Cookie", cookie);
        }
        HttpResponse<String> response = httpClient.send(requestBuilder.build(),
                HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
        if (response.statusCode() < 200 || response.statusCode() >= 300) {
            log.warn("QQ音乐API请求失败: status={}", response.statusCode());
            return null;
        }
        return JSONObject.parseObject(response.body());
    }

    /**
     * 发送 HTTP POST 请求并解析 JSON 响应。
     *
     * @param url     请求 URL
     * @param bodyJson 请求体 JSON 字符串
     * @return JSON 响应，失败返回 null
     */
    private JSONObject postJson(String url, String bodyJson, String cookie)
            throws IOException, InterruptedException {
        HttpRequest.Builder requestBuilder = HttpRequest.newBuilder(URI.create(url))
                .timeout(REQUEST_TIMEOUT)
                .header("Accept", "application/json")
                .header("Content-Type", "application/json")
                .header("Referer", "https://y.qq.com/")
                .POST(HttpRequest.BodyPublishers.ofString(bodyJson, StandardCharsets.UTF_8));
        if (cookie != null && !cookie.isBlank()) {
            requestBuilder.header("Cookie", cookie);
        }
        HttpResponse<String> response = httpClient.send(requestBuilder.build(),
                HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
        if (response.statusCode() < 200 || response.statusCode() >= 300) {
            log.warn("QQ音乐API POST请求失败: status={}", response.statusCode());
            return null;
        }
        return JSONObject.parseObject(response.body());
    }

    /**
     * 从 Cookie 字符串中提取 uin。
     *
     * @param cookie Cookie 字符串
     * @return 纯数字 uin，未找到返回 null
     */
    private String extractUin(String cookie) {
        String[] parts = cookie.split(";");
        for (String part : parts) {
            String trimmed = part.trim();
            if (trimmed.startsWith("uin=")) {
                String value = trimmed.substring(4).trim();
                Matcher matcher = UIN_PATTERN.matcher(value);
                if (matcher.matches()) {
                    return matcher.group(1);
                }
                return value;
            }
        }
        return null;
    }

    /**
     * 根据文件扩展名判断音频格式。
     */
    private String guessFormat(String filename) {
        if (filename == null) {
            return "unknown";
        }
        String lower = filename.toLowerCase();
        if (lower.endsWith(".flac")) {
            return "flac";
        }
        if (lower.endsWith(".mp3")) {
            return "mp3";
        }
        if (lower.endsWith(".m4a")) {
            return "m4a";
        }
        return "unknown";
    }

    /**
     * 根据文件名前缀检测音质等级。
     */
    private String detectQuality(String filename) {
        if (filename == null) {
            return "unknown";
        }
        for (QualityTemplate template : QUALITY_TEMPLATES) {
            if (filename.startsWith(template.prefix)) {
                return template.quality;
            }
        }
        return "unknown";
    }

    /**
     * 根据请求音质确定探测起始索引。
     */
    private int startIndexForQuality(String quality) {
        if (quality == null || quality.isBlank()) {
            return 0;
        }
        String normalized = quality.trim().toLowerCase();
        for (int i = 0; i < QUALITY_TEMPLATES.size(); i++) {
            if (QUALITY_TEMPLATES.get(i).quality().equals(normalized)) {
                return i;
            }
        }
        return 0;
    }

    /**
     * Base64 解码。
     */
    private String decodeBase64(String encoded) {
        if (encoded == null || encoded.isBlank()) {
            return null;
        }
        try {
            return new String(Base64.getDecoder().decode(encoded), StandardCharsets.UTF_8);
        } catch (IllegalArgumentException ex) {
            log.warn("QQ音乐Base64解码失败: message={}", ex.getMessage());
            return null;
        }
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

    private MusicPlatformCredential credential(UUID ownerUserId) {
        return credentialService.find(ownerUserId, MusicPlatform.QQ)
                .orElseGet(() -> new MusicPlatformCredential(null, null, emptyUserInfo(), null));
    }

    private PlatformUserInfo emptyUserInfo() {
        return new PlatformUserInfo(MusicPlatform.QQ.apiValue(), "", "", "", false);
    }

    /**
     * 搜索候选记录。
     */
    private record SongCandidate(String songMid, String songName, String singerName) {
    }

    /**
     * 音质模板定义。
     */
    private record QualityTemplate(String prefix, String extension, String quality, String description) {
    }
}
