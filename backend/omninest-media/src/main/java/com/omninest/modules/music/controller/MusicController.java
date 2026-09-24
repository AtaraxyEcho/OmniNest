package com.omninest.modules.music.controller;

import com.omninest.common.api.ApiResponse;
import com.omninest.common.api.PageResponse;
import com.omninest.common.security.CurrentUserContext;
import com.omninest.common.security.Permissions;
import com.omninest.modules.file.dto.FilePurgeTaskDto;
import com.omninest.modules.music.dto.MusicDtos.CreatePlaylistRequest;
import com.omninest.modules.music.dto.MusicDtos.MusicAlbumDto;
import com.omninest.modules.music.dto.MusicDtos.MusicArtistDto;
import com.omninest.modules.music.dto.MusicDtos.MusicDashboardDto;
import com.omninest.modules.music.dto.MusicDtos.MusicCoverUploadDto;
import com.omninest.modules.music.dto.MusicDtos.MusicPlayHistoryRequest;
import com.omninest.modules.music.dto.MusicDtos.MusicPlayHistoryDto;
import com.omninest.modules.music.dto.MusicDtos.MusicRecentItemDto;
import com.omninest.modules.music.dto.MusicDtos.MusicPlaylistDto;
import com.omninest.modules.music.dto.MusicDtos.MusicPlaybackPlanDto;
import com.omninest.modules.music.dto.MusicDtos.MusicPlaybackProgressDto;
import com.omninest.modules.music.dto.MusicDtos.MusicPlaybackQueueDto;
import com.omninest.modules.music.dto.MusicDtos.MusicScanJobDto;
import com.omninest.modules.music.dto.MusicDtos.MusicScrapeApplyRequest;
import com.omninest.modules.music.dto.MusicDtos.MusicScrapeCandidateDto;
import com.omninest.modules.music.dto.MusicDtos.MusicScrapeRequest;
import com.omninest.modules.music.dto.MusicDtos.MusicSearchResultDto;
import com.omninest.modules.music.dto.MusicDtos.MusicTrackDto;
import com.omninest.modules.music.dto.MusicDtos.PlaylistItemsRequest;
import com.omninest.modules.music.dto.MusicDtos.PlaybackPositionDto;
import com.omninest.modules.music.dto.MusicDtos.RecordMusicPlayHistoryRequest;
import com.omninest.modules.music.dto.MusicDtos.SavePositionRequest;
import com.omninest.modules.music.dto.MusicDtos.SaveMusicPlaybackProgressRequest;
import com.omninest.modules.music.dto.MusicDtos.SaveMusicPlaybackQueueRequest;
import com.omninest.modules.music.dto.MusicDtos.UpdateMusicTrackRequest;
import com.omninest.modules.music.dto.MusicDtos.UpdatePlaylistRequest;
import com.omninest.modules.music.dto.OnlineMusicDtos.DailyRecommendedTracksDto;
import com.omninest.modules.music.dto.OnlineMusicDtos.MusicPlatformStatusDto;
import com.omninest.modules.music.dto.OnlineMusicDtos.OnlinePlaylistDto;
import com.omninest.modules.music.dto.OnlineMusicDtos.OnlineTrackDto;
import com.omninest.modules.music.dto.OnlineMusicDtos.PlatformUserInfo;
import com.omninest.modules.music.dto.OnlineMusicDtos.QrLoginSession;
import com.omninest.modules.music.dto.OnlineMusicDtos.QrLoginStatus;
import com.omninest.modules.music.service.LrclibLyricsService;
import com.omninest.modules.music.service.MusicAdminService;
import com.omninest.modules.music.service.MusicCoverService;
import com.omninest.modules.music.service.MusicLibraryService;
import com.omninest.modules.music.service.MusicPlatformAccountService;
import com.omninest.modules.music.service.MusicOnlineDispatcher;
import com.omninest.modules.music.service.MusicPlatformService;
import com.omninest.modules.music.service.MusicPlaybackService;
import com.omninest.modules.music.service.MusicPlaybackQueueService;
import com.omninest.modules.music.service.MusicPlaylistService;
import com.omninest.modules.music.service.MusicScrapeService;
import com.omninest.modules.music.service.MusicStreamGatewayService;
import com.omninest.modules.music.service.platform.MusicPlatformProvider.LyricsResult;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.Size;
import java.net.URI;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.servlet.mvc.method.annotation.StreamingResponseBody;
import org.springframework.web.multipart.MultipartFile;

/**
 * 提供音乐曲库、平台连接和播放会话接口。
 *
 * @author OmniNest
 */
@Tag(name = "音乐库", description = "音乐资源管理与播放")
@RestController
@Validated
@RequiredArgsConstructor
@Slf4j
public class MusicController {
    /** 稳定封面路径可被客户端私有缓存无限期复用。 */
    private static final String IMMUTABLE_CACHE_CONTROL = "private, max-age=2592000, immutable";

    /** 缩略图回退且不会再有缩略图：按天缓存，既不让大原图反复下载，也留出更正机会。 */
    private static final String THUMBNAIL_STABLE_FALLBACK_CACHE_CONTROL = "private, max-age=86400";

    /** 缩略图回退且值得重试（派生繁忙或临时失败）：只缓存一分钟，下次进入即拿到缩略图。 */
    private static final String THUMBNAIL_RETRY_CACHE_CONTROL = "private, max-age=60";

    /**
     * 异步封面接口的占位响应头。
     *
     * <p>Spring Security 的默认写头在异步派发返回时执行，那时业务响应头尚未就绪，
     * 它会补上 {@code no-cache, no-store, max-age=0}；之后再写 Cache-Control 只会追加，
     * 客户端按第一个取值判断，稳定缩略图路径因此永远不新鲜。这里先占位抑制该写头，
     * 派生完成后覆盖为真实新鲜度；失败路径保留本值，错误响应依旧不可缓存。</p>
     */
    private static final String UNCACHEABLE_CACHE_CONTROL = "no-store";

    private final CurrentUserContext currentUserContext;
    private final MusicOnlineDispatcher onlineDispatcher;
    private final MusicLibraryService musicLibraryService;
    private final MusicPlaylistService playlistService;
    private final MusicAdminService musicAdminService;
    private final MusicCoverService musicCoverService;
    private final MusicScrapeService musicScrapeService;
    private final MusicPlaybackService playbackService;
    private final MusicPlaybackQueueService playbackQueueService;
    private final LrclibLyricsService lrclibLyricsService;
    private final MusicPlatformService musicPlatformService;
    private final MusicPlatformAccountService musicPlatformAccountService;
    private final MusicStreamGatewayService musicStreamGatewayService;

    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/music/dashboard")
    ApiResponse<MusicDashboardDto> dashboard() {
        return ApiResponse.success(musicLibraryService.dashboard(currentUserContext.requireCurrentUserId()));
    }

    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/music/search")
    ApiResponse<MusicSearchResultDto> search(@RequestParam(defaultValue = "") String q) {
        return ApiResponse.success(musicLibraryService.search(currentUserContext.requireCurrentUserId(), q));
    }

    @Operation(summary = "分页查询曲目", description = "按白名单字段分页列出当前用户可见的曲目")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/music/tracks")
    ApiResponse<PageResponse<MusicTrackDto>> tracks(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "100") int size,
            @RequestParam(defaultValue = "title,asc") String sort) {
        var result = musicLibraryService.tracks(currentUserContext.requireCurrentUserId(), page, size, sort);
        return ApiResponse.success(PageResponse.of(
                result.getContent(),
                result.getNumber(),
                result.getSize(),
                result.getTotalElements()));
    }

    @Operation(summary = "分页查询专辑", description = "按白名单字段分页列出至少包含一个活动曲目的专辑")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/music/albums")
    ApiResponse<PageResponse<MusicAlbumDto>> albums(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "100") int size,
            @RequestParam(defaultValue = "updatedAt,desc") String sort) {
        var result = musicLibraryService.albums(currentUserContext.requireCurrentUserId(), page, size, sort);
        return ApiResponse.success(PageResponse.of(
                result.getContent(),
                result.getNumber(),
                result.getSize(),
                result.getTotalElements()));
    }

    @Operation(summary = "分页查询艺术家", description = "按名称分页列出至少包含一个活动曲目的艺术家")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/music/artists")
    ApiResponse<PageResponse<MusicArtistDto>> artists(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "100") int size,
            @RequestParam(defaultValue = "name,asc") String sort) {
        var result = musicLibraryService.artists(currentUserContext.requireCurrentUserId(), page, size, sort);
        return ApiResponse.success(PageResponse.of(
                result.getContent(),
                result.getNumber(),
                result.getSize(),
                result.getTotalElements()));
    }

    @Operation(summary = "查询专辑全部曲目", description = "按碟号与音轨号返回专辑内全部可见曲目，用于播放队列按来源重建")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/music/albums/{albumId}/tracks")
    ApiResponse<List<MusicTrackDto>> albumTracks(@PathVariable UUID albumId) {
        return ApiResponse.success(musicLibraryService.albumTracks(
                currentUserContext.requireCurrentUserId(), albumId));
    }

    @Operation(summary = "查询艺术家全部曲目", description = "按专辑名与碟号、音轨号返回艺术家全部可见曲目，用于播放队列按来源重建")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/music/artists/{artistId}/tracks")
    ApiResponse<List<MusicTrackDto>> artistTracks(@PathVariable UUID artistId) {
        return ApiResponse.success(musicLibraryService.artistTracks(
                currentUserContext.requireCurrentUserId(), artistId));
    }

    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/music/favorites")
    ApiResponse<List<MusicTrackDto>> favorites() {
        return ApiResponse.success(musicLibraryService.favorites(currentUserContext.requireCurrentUserId()));
    }

    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/music/recent")
    ApiResponse<List<MusicTrackDto>> recent() {
        return ApiResponse.success(musicLibraryService.recent(currentUserContext.requireCurrentUserId()));
    }

    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/music/recent-items")
    ApiResponse<List<MusicRecentItemDto>> recentItems() {
        return ApiResponse.success(musicLibraryService.recentItems(currentUserContext.requireCurrentUserId()));
    }

    @Operation(summary = "查询艺术家专辑", description = "返回指定艺术家下至少包含一个活动曲目的专辑")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/music/artists/{artistId}/albums")
    ApiResponse<List<MusicAlbumDto>> artistAlbums(@PathVariable UUID artistId) {
        return ApiResponse.success(musicLibraryService.artistAlbums(
                currentUserContext.requireCurrentUserId(),
                artistId));
    }

    @Operation(summary = "分页查询播放历史", description = "按播放时间倒序分页返回当前用户的播放历史")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/music/history")
    ApiResponse<PageResponse<MusicPlayHistoryDto>> history(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "50") int size) {
        var result = musicLibraryService.playHistory(currentUserContext.requireCurrentUserId(), page, size);
        return ApiResponse.success(PageResponse.of(
                result.getContent(),
                result.getNumber(),
                result.getSize(),
                result.getTotalElements()));
    }

    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/music/stream/{trackId}")
    ResponseEntity<Void> stream(@PathVariable UUID trackId) {
        MusicPlaybackPlanDto plan = playbackService.playbackPlan(currentUserContext.requireCurrentUserId(), trackId);
        return ResponseEntity.status(HttpStatus.FOUND).location(URI.create(plan.url())).build();
    }

    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/music/tracks/{trackId}/playback-plan")
    ApiResponse<MusicPlaybackPlanDto> playbackPlan(@PathVariable UUID trackId) {
        return ApiResponse.success(playbackService.playbackPlan(currentUserContext.requireCurrentUserId(), trackId));
    }

    @GetMapping("/api/v1/music/playback/sessions/{sessionId}/stream")
    ResponseEntity<StreamingResponseBody> playbackSessionStream(
            @PathVariable String sessionId,
            @RequestParam String token,
            @RequestHeader(value = "Range", required = false) String range
    ) {
        return musicStreamGatewayService.stream(sessionId, token, range);
    }

    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    @DeleteMapping("/api/v1/music/tracks/{trackId}")
    ApiResponse<FilePurgeTaskDto> deleteTrack(
            @PathVariable UUID trackId,
            @RequestParam(defaultValue = "false") boolean cascade
    ) {
        UUID taskId = musicLibraryService.deleteTrack(
                currentUserContext.requireCurrentUserId(),
                trackId,
                cascade
        );
        return ApiResponse.success(FilePurgeTaskDto.queued(taskId));
    }

    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    @PostMapping("/api/v1/music/tracks/{trackId}/favorite")
    ApiResponse<MusicTrackDto> favorite(@PathVariable UUID trackId) {
        return ApiResponse.success(musicLibraryService.favorite(currentUserContext.requireCurrentUserId(), trackId));
    }

    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    @DeleteMapping("/api/v1/music/tracks/{trackId}/favorite")
    ApiResponse<MusicTrackDto> removeFavorite(@PathVariable UUID trackId) {
        return ApiResponse.success(musicLibraryService.removeFavorite(currentUserContext.requireCurrentUserId(), trackId));
    }

    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    @PostMapping("/api/v1/music/tracks/{trackId}/play-history")
    ApiResponse<Void> playHistory(@PathVariable UUID trackId, @RequestBody(required = false) MusicPlayHistoryRequest request) {
        musicLibraryService.recordPlayHistory(currentUserContext.requireCurrentUserId(), trackId, request);
        return ApiResponse.success();
    }

    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    @PostMapping("/api/v1/music/play-history")
    ApiResponse<Void> playHistory(@Valid @RequestBody RecordMusicPlayHistoryRequest request) {
        musicLibraryService.recordPlayHistory(currentUserContext.requireCurrentUserId(), request);
        return ApiResponse.success();
    }

    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/music/last-played")
    ApiResponse<MusicTrackDto> lastPlayed() {
        MusicTrackDto track = musicLibraryService.getLastPlayed(currentUserContext.requireCurrentUserId());
        return ApiResponse.success(track);
    }

    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/music/last-position")
    ApiResponse<PlaybackPositionDto> lastPosition() {
        PlaybackPositionDto position = playbackService.getLastPosition(currentUserContext.requireCurrentUserId());
        return ApiResponse.success(position);
    }

    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    @PutMapping("/api/v1/music/position")
    ApiResponse<Void> savePosition(@RequestBody SavePositionRequest request) {
        playbackService.savePosition(currentUserContext.requireCurrentUserId(), request.trackId(), request.positionSeconds());
        return ApiResponse.success();
    }

    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/music/progress")
    ApiResponse<MusicPlaybackProgressDto> musicProgress(
            @RequestParam @Size(max = 512) String playableKey
    ) {
        return ApiResponse.success(playbackService.getProgress(
                currentUserContext.requireCurrentUserId(),
                playableKey
        ));
    }

    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    @PutMapping("/api/v1/music/progress")
    ApiResponse<MusicPlaybackProgressDto> saveMusicProgress(
            @Valid @RequestBody SaveMusicPlaybackProgressRequest request
    ) {
        return ApiResponse.success(playbackService.saveProgress(
                currentUserContext.requireCurrentUserId(),
                request
        ));
    }

    @Operation(summary = "获取上次音乐播放队列")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/music/playback-queue")
    ApiResponse<MusicPlaybackQueueDto> playbackQueue() {
        return ApiResponse.success(playbackQueueService.load(
                currentUserContext.requireCurrentUserId()
        ));
    }

    @Operation(summary = "保存当前音乐播放队列")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    @PutMapping("/api/v1/music/playback-queue")
    ApiResponse<MusicPlaybackQueueDto> savePlaybackQueue(
            @Valid @RequestBody SaveMusicPlaybackQueueRequest request
    ) {
        return ApiResponse.success(playbackQueueService.save(
                currentUserContext.requireCurrentUserId(),
                request
        ));
    }

    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/music/playlists")
    ApiResponse<List<MusicPlaylistDto>> playlists() {
        return ApiResponse.success(playlistService.playlists(currentUserContext.requireCurrentUserId()));
    }

    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    @PostMapping("/api/v1/music/playlists")
    ApiResponse<MusicPlaylistDto> createPlaylist(@Valid @RequestBody CreatePlaylistRequest request) {
        return ApiResponse.success(playlistService.create(currentUserContext.requireCurrentUserId(), request));
    }

    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    @PutMapping("/api/v1/music/playlists/{playlistId}")
    ApiResponse<MusicPlaylistDto> updatePlaylist(@PathVariable UUID playlistId, @Valid @RequestBody UpdatePlaylistRequest request) {
        return ApiResponse.success(playlistService.update(currentUserContext.requireCurrentUserId(), playlistId, request));
    }

    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    @DeleteMapping("/api/v1/music/playlists/{playlistId}")
    ApiResponse<Void> deletePlaylist(@PathVariable UUID playlistId) {
        playlistService.delete(currentUserContext.requireCurrentUserId(), playlistId);
        return ApiResponse.success();
    }

    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/music/playlists/{playlistId}/items")
    ApiResponse<List<MusicTrackDto>> playlistTracks(@PathVariable UUID playlistId) {
        return ApiResponse.success(playlistService.playlistTracks(currentUserContext.requireCurrentUserId(), playlistId));
    }

    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    @PostMapping("/api/v1/music/playlists/{playlistId}/items")
    ApiResponse<MusicPlaylistDto> addPlaylistItems(@PathVariable UUID playlistId, @Valid @RequestBody PlaylistItemsRequest request) {
        return ApiResponse.success(playlistService.addItems(currentUserContext.requireCurrentUserId(), playlistId, request));
    }

    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    @DeleteMapping("/api/v1/music/playlists/{playlistId}/items")
    ApiResponse<MusicPlaylistDto> removePlaylistItems(
            @PathVariable UUID playlistId,
            @Valid @RequestBody PlaylistItemsRequest request
    ) {
        return ApiResponse.success(playlistService.removeItems(
                currentUserContext.requireCurrentUserId(),
                playlistId,
                request
        ));
    }

    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    @Operation(summary = "上传音乐封面", description = "校验图片内容并保存为当前用户的音乐封面资产")
    @PostMapping(value = "/api/v1/music/covers", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    ApiResponse<MusicCoverUploadDto> uploadMusicCover(@RequestParam("file") MultipartFile file) {
        return ApiResponse.success(musicCoverService.upload(
                currentUserContext.requireCurrentUserId(),
                file
        ));
    }

    /**
     * 流式下载音乐封面：鉴权后经统一内容访问接口回源，供客户端内嵌渲染。
     *
     * <p>路径永久稳定（封面重传会生成新文件标识），配合 immutable 缓存指令
     * 允许客户端私有缓存长期复用，替代此前每次组装重签的短期下载地址。
     */
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @Operation(summary = "下载音乐封面", description = "校验归属后流式返回封面内容，路径稳定可长期缓存")
    @GetMapping("/api/v1/music/covers/{fileId}")
    ResponseEntity<StreamingResponseBody> downloadMusicCover(@PathVariable UUID fileId) {
        MusicCoverService.CoverStreamDescriptor descriptor = musicCoverService.prepareCoverStream(
                currentUserContext.requireCurrentUserId(),
                fileId
        );
        StreamingResponseBody body = outputStream -> musicCoverService.streamCover(descriptor, outputStream);
        return ResponseEntity.ok()
                .contentType(MediaType.parseMediaType(descriptor.contentType()))
                .contentLength(descriptor.sizeBytes())
                .header(HttpHeaders.CACHE_CONTROL, IMMUTABLE_CACHE_CONTROL)
                .body(body);
    }

    /**
     * 流式下载音乐封面缩略图：首次访问时按需派生 300px 版本，之后按稳定路径长期缓存。
     *
     * <p>派生要解码原图，因此整段准备放在音乐线程池执行，请求线程只承担鉴权与参数解析。
     * 路径同样永久稳定：缩略图按封面文件标识定位，封面重传会生成新的文件标识。</p>
     */
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @Operation(summary = "下载音乐封面缩略图", description = "按需派生并流式返回 300px 封面，原图不受理时回退原图")
    @GetMapping("/api/v1/music/covers/{fileId}/thumbnail")
    CompletableFuture<ResponseEntity<StreamingResponseBody>> downloadMusicCoverThumbnail(
            @PathVariable UUID fileId,
            HttpServletResponse response
    ) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        response.setHeader(HttpHeaders.CACHE_CONTROL, UNCACHEABLE_CACHE_CONTROL);
        return onlineDispatcher.supply(() -> {
            MusicCoverService.ThumbnailStream thumbnail = musicCoverService.prepareThumbnailStream(
                    ownerUserId,
                    fileId
            );
            MusicCoverService.CoverStreamDescriptor descriptor = thumbnail.descriptor();
            StreamingResponseBody body = outputStream -> musicCoverService.streamCover(descriptor, outputStream);
            response.setHeader(HttpHeaders.CACHE_CONTROL, coverCacheControl(thumbnail.freshness()));
            return ResponseEntity.ok()
                    .contentType(MediaType.parseMediaType(descriptor.contentType()))
                    .contentLength(descriptor.sizeBytes())
                    .body(body);
        });
    }

    private static String coverCacheControl(MusicCoverService.ThumbnailFreshness freshness) {
        return switch (freshness) {
            case DERIVED -> IMMUTABLE_CACHE_CONTROL;
            case STABLE_FALLBACK -> THUMBNAIL_STABLE_FALLBACK_CACHE_CONTROL;
            case RETRY_SOON -> THUMBNAIL_RETRY_CACHE_CONTROL;
        };
    }

    @PostMapping("/api/v1/admin/music/scan")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    ApiResponse<MusicScanJobDto> createScanJob() {
        return ApiResponse.success(musicAdminService.createScanJob(currentUserContext.requireCurrentUserId()));
    }

    @GetMapping("/api/v1/admin/music/scan/{jobId}/status")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    ApiResponse<MusicScanJobDto> scanJob(@PathVariable UUID jobId) {
        return ApiResponse.success(musicAdminService.scanJob(currentUserContext.requireCurrentUserId(), jobId));
    }

    @PutMapping("/api/v1/admin/music/tracks/{trackId}")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    ApiResponse<MusicTrackDto> updateTrack(@PathVariable UUID trackId, @Valid @RequestBody UpdateMusicTrackRequest request) {
        return ApiResponse.success(musicAdminService.updateTrack(currentUserContext.requireCurrentUserId(), trackId, request));
    }

    @GetMapping("/api/v1/admin/music/tracks/{trackId}/scrape-candidates")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    ApiResponse<List<MusicScrapeCandidateDto>> scrapeCandidates(@PathVariable UUID trackId) {
        return ApiResponse.success(musicScrapeService.candidates(currentUserContext.requireCurrentUserId(), trackId));
    }

    @PostMapping("/api/v1/admin/music/tracks/{trackId}/scrape/apply")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    ApiResponse<MusicTrackDto> applyScrapeCandidate(
            @PathVariable UUID trackId,
            @Valid @RequestBody MusicScrapeApplyRequest request
    ) {
        return ApiResponse.success(musicScrapeService.applyCandidate(currentUserContext.requireCurrentUserId(), trackId, request));
    }

    @PostMapping("/api/v1/admin/music/scrape")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    ApiResponse<MusicScanJobDto> scrapeLibrary(@RequestBody(required = false) MusicScrapeRequest request) {
        boolean force = request != null && request.force();
        return ApiResponse.success(musicScrapeService.scrapeLibrary(currentUserContext.requireCurrentUserId(), force));
    }

    @GetMapping("/api/v1/admin/music/tracks/{trackId}/lyrics/search")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    ApiResponse<LrclibLyricsService.LyricsResult> searchLyrics(@PathVariable UUID trackId) {
        var track = musicLibraryService.requireTrack(currentUserContext.requireCurrentUserId(), trackId);
        LrclibLyricsService.LyricsResult result = lrclibLyricsService.search(
                track.getArtistName(), track.getTitle(), track.getAlbumTitle());
        if (result == null) {
            return ApiResponse.success(null);
        }
        return ApiResponse.success(result);
    }

    @PostMapping("/api/v1/admin/music/tracks/{trackId}/lyrics/apply")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    ApiResponse<MusicTrackDto> applyLyrics(
            @PathVariable UUID trackId,
            @RequestBody ApplyLyricsRequest request
    ) {
        return ApiResponse.success(musicAdminService.applyLyrics(
                currentUserContext.requireCurrentUserId(),
                trackId,
                request.lyrics(),
                request.lyricsTranslation()));
    }

    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/music/online/search")
    CompletableFuture<ApiResponse<List<OnlineTrackDto>>> onlineSearch(
            @RequestParam @Size(max = 200) String q,
            @RequestParam(defaultValue = "20") @Min(1) @Max(50) int limit,
            @RequestParam(required = false) @Size(max = 32) String platform
    ) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        if (platform != null && !platform.isBlank()) {
            return onlineDispatcher.online(
                    () -> musicPlatformService.search(ownerUserId, q, limit, platform));
        }
        return onlineDispatcher.online(
                () -> musicPlatformService.search(ownerUserId, q, limit));
    }

    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/music/online/playback-plan")
    CompletableFuture<ApiResponse<MusicPlaybackPlanDto>> onlinePlaybackPlan(
            @RequestParam @Size(max = 32) String platform,
            @RequestParam @Size(max = 255) String songId,
            @RequestParam(required = false) @Size(max = 255) String mediaMid,
            @RequestParam(defaultValue = "high") @Size(max = 32) String quality
    ) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        return onlineDispatcher.online(() -> playbackService.onlinePlaybackPlan(
                ownerUserId,
                platform,
                songId,
                mediaMid,
                quality
        ));
    }

    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/music/platforms")
    ApiResponse<List<MusicPlatformStatusDto>> musicPlatforms() {
        return ApiResponse.success(musicPlatformAccountService.platforms(
                currentUserContext.requireCurrentUserId()
        ));
    }

    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    @PostMapping("/api/v1/music/platforms/netease/login-sessions")
    ApiResponse<QrLoginSession> createNeteaseLoginSession() {
        return ApiResponse.success(musicPlatformAccountService.createNeteaseQrLogin(
                currentUserContext.requireCurrentUserId()
        ));
    }

    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/music/platforms/netease/login-sessions/{sessionId}")
    ApiResponse<QrLoginStatus> neteaseLoginSession(
            @PathVariable @Size(max = 512) String sessionId
    ) {
        return ApiResponse.success(musicPlatformAccountService.checkNeteaseQrLogin(
                currentUserContext.requireCurrentUserId(),
                sessionId
        ));
    }


    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    @DeleteMapping("/api/v1/music/platforms/{platform}/connection")
    ApiResponse<Void> disconnectPlatform(@PathVariable @Size(max = 32) String platform) {
        // 平台派生状态（每日推荐缓存、播放队列条目、登录会话）的清理已收编在
        // service 内，保证与 DELETE / POST 两个注销入口行为一致。
        musicPlatformAccountService.disconnect(
                currentUserContext.requireCurrentUserId(),
                platform
        );
        return ApiResponse.success();
    }

    @Operation(summary = "获取外部平台每日推荐歌曲")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/music/platforms/{platform}/recommendations/daily-tracks")
    CompletableFuture<ApiResponse<DailyRecommendedTracksDto>> dailyRecommendedTracks(
            @PathVariable @Size(max = 32) String platform
    ) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        return onlineDispatcher.online(() -> musicPlatformService.dailyRecommendedTracks(
                ownerUserId,
                platform
        ));
    }

    @Operation(summary = "分页获取外部平台歌单")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/music/platforms/{platform}/playlists")
    CompletableFuture<ApiResponse<PageResponse<OnlinePlaylistDto>>> platformPlaylists(
            @PathVariable @Size(max = 32) String platform,
            @RequestParam(defaultValue = "0") @Min(0) int page,
            @RequestParam(defaultValue = "100") @Min(1) @Max(200) int size,
            @RequestParam(defaultValue = "false") boolean refresh
    ) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        return onlineDispatcher.online(() -> musicPlatformService.playlists(
                ownerUserId,
                platform,
                page,
                size,
                refresh
        ));
    }

    @Operation(summary = "分页获取外部平台歌单曲目")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/music/platforms/{platform}/playlists/{playlistId}/tracks")
    CompletableFuture<ApiResponse<PageResponse<OnlineTrackDto>>> platformPlaylistTracks(
            @PathVariable @Size(max = 32) String platform,
            @PathVariable @Size(max = 255) String playlistId,
            @RequestParam(defaultValue = "0") @Min(0) int page,
            @RequestParam(defaultValue = "1000") @Min(1) @Max(1000) int size,
            @RequestParam(defaultValue = "false") boolean refresh
    ) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        return onlineDispatcher.online(() -> musicPlatformService.playlistTracks(
                ownerUserId,
                platform,
                playlistId,
                page,
                size,
                refresh
        ));
    }

    @Operation(summary = "分页获取外部平台喜欢歌曲")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/music/platforms/{platform}/liked-tracks")
    CompletableFuture<ApiResponse<PageResponse<OnlineTrackDto>>> platformLikedTracks(
            @PathVariable @Size(max = 32) String platform,
            @RequestParam(defaultValue = "0") @Min(0) int page,
            @RequestParam(defaultValue = "1000") @Min(1) @Max(1000) int size,
            @RequestParam(defaultValue = "false") boolean refresh
    ) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        return onlineDispatcher.online(() -> musicPlatformService.likedTracks(
                ownerUserId,
                platform,
                page,
                size,
                refresh
        ));
    }

    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/music/platforms/{platform}/tracks/{songId}/lyrics")
    CompletableFuture<ApiResponse<LyricsResult>> platformTrackLyrics(
            @PathVariable @Size(max = 32) String platform,
            @PathVariable @Size(max = 255) String songId
    ) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        return onlineDispatcher.online(() -> musicPlatformService.getLyrics(
                ownerUserId,
                platform,
                songId
        ));
    }

    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    @PostMapping("/api/v1/music/platform/netease/login/qr")
    ApiResponse<QrLoginSession> createNeteaseQrLogin() {
        return ApiResponse.success(musicPlatformAccountService.createNeteaseQrLogin(
                currentUserContext.requireCurrentUserId()
        ));
    }

    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/music/platform/netease/login/qr/check")
    ApiResponse<QrLoginStatus> checkNeteaseQrLogin(@RequestParam @Size(max = 512) String key) {
        return ApiResponse.success(musicPlatformAccountService.checkNeteaseQrLogin(
                currentUserContext.requireCurrentUserId(),
                key
        ));
    }


    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    @PostMapping("/api/v1/music/platform/{platform}/logout")
    ApiResponse<Void> platformLogout(@PathVariable String platform) {
        musicPlatformAccountService.disconnect(currentUserContext.requireCurrentUserId(), platform);
        return ApiResponse.success();
    }

    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/music/platform/{platform}/info")
    CompletableFuture<ApiResponse<PlatformUserInfo>> platformInfo(
            @PathVariable String platform
    ) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        return onlineDispatcher.online(() -> musicPlatformAccountService.getUserInfo(
                ownerUserId,
                platform
        ));
    }

    public record ApplyLyricsRequest(String lyrics, String lyricsTranslation) {
    }
}

