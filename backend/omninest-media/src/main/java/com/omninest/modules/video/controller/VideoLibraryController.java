package com.omninest.modules.video.controller;

import com.omninest.common.api.ApiResponse;
import com.omninest.common.api.PageResponse;
import com.omninest.common.security.CurrentUserContext;
import com.omninest.common.security.Permissions;
import com.omninest.modules.file.dto.FilePurgeTaskDto;
import com.omninest.modules.video.dto.MovieDtos.MovieContentAssetDto;
import com.omninest.modules.video.dto.MovieDtos.MovieDashboardDto;
import com.omninest.modules.video.dto.MovieDtos.MovieCollectionDto;
import com.omninest.modules.video.dto.MovieDtos.MovieCollectionItemRequest;
import com.omninest.modules.video.dto.MovieDtos.MovieCollectionRequest;
import com.omninest.modules.video.dto.MovieDtos.MovieContinueWatchingDto;
import com.omninest.modules.video.dto.MovieDtos.MovieFavoriteStateDto;
import com.omninest.modules.video.dto.MovieDtos.MovieLibraryItemDto;
import com.omninest.modules.video.dto.MovieDtos.MovieMetadataUpdateRequest;
import com.omninest.modules.video.dto.MovieDtos.MovieScanRequest;
import com.omninest.modules.video.dto.MovieDtos.MovieSeasonDetailDto;
import com.omninest.modules.video.dto.MovieDtos.MovieSeriesDto;
import com.omninest.modules.video.dto.MovieDtos.UpdateSeriesMetadataRequest;
import com.omninest.modules.video.dto.MovieDtos.MovieSeriesDetailDto;
import com.omninest.modules.video.dto.MovieDtos.MovieTaskDto;
import com.omninest.modules.video.dto.MovieDtos.MovieVideoItemDto;
import com.omninest.modules.video.dto.MovieDtos.MovieWatchHistoryDto;
import com.omninest.modules.video.dto.MovieDtos.NfoExportDto;
import com.omninest.modules.video.dto.MovieDtos.PlaybackPlanDto;
import com.omninest.modules.video.dto.MovieDtos.PlaybackProgressRequest;
import com.omninest.modules.video.dto.MovieDtos.ScrapeCandidateDto;
import com.omninest.modules.video.dto.MovieDtos.ScrapeRequest;
import com.omninest.modules.video.dto.MovieDtos.ScrapeTaskDto;
import com.omninest.modules.video.dto.MovieDtos.SubtitleTrackDto;
import com.omninest.modules.video.dto.MovieDtos.SubtitleUpdateRequest;
import com.omninest.modules.video.dto.MovieDtos.SubtitleUploadRequest;
import com.omninest.modules.video.service.MediaPlaybackTokenService;
import com.omninest.modules.video.service.MovieEngagementService;
import com.omninest.modules.video.service.MovieLibraryService;
import com.omninest.modules.video.service.MovieNfoService;
import com.omninest.modules.video.service.MoviePlaybackService;
import com.omninest.modules.video.service.MovieScrapeService;
import com.omninest.modules.video.service.MovieTaskService;
import com.omninest.modules.video.service.SubtitleManagementService;
import com.omninest.modules.video.service.VideoProbeService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.validation.Valid;
import java.io.IOException;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@Tag(name = "视频库", description = "视频资源的管理与元数据操作")
@RestController
@RequiredArgsConstructor
public class VideoLibraryController {
    private final CurrentUserContext currentUserContext;
    private final MovieLibraryService movieLibraryService;
    private final MoviePlaybackService moviePlaybackService;
    private final MovieScrapeService movieScrapeService;
    private final MovieNfoService movieNfoService;
    private final MovieEngagementService movieEngagementService;
    private final MovieTaskService movieTaskService;
    private final SubtitleManagementService subtitleManagementService;
    private final VideoProbeService videoProbeService;
    private final MediaPlaybackTokenService mediaPlaybackTokenService;

    @Operation(summary = "获取视频仪表盘", description = "返回用户的视频概览信息，包括最近观看、收藏数量等")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/video/dashboard")
    ApiResponse<MovieDashboardDto> dashboard() {
        return ApiResponse.success(movieLibraryService.dashboard(currentUserContext.requireCurrentUserId()));
    }

    @Operation(summary = "获取视频库", description = "按媒体类型（电影、剧集）返回用户的视频列表")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/video/library")
    @Deprecated(forRemoval = false)
    ApiResponse<List<MovieVideoItemDto>> library(@RequestParam(defaultValue = "MOVIE") String mediaType) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        if ("EPISODE".equalsIgnoreCase(mediaType) || "TVSHOW".equalsIgnoreCase(mediaType)) {
            return ApiResponse.success(movieLibraryService.episodes(ownerUserId));
        }
        return ApiResponse.success(movieLibraryService.movies(ownerUserId));
    }

    @Operation(summary = "分页获取视频库", description = "按媒体类型分页返回影视库卡片所需的轻量数据")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/video/library/page")
    ApiResponse<PageResponse<MovieLibraryItemDto>> libraryPage(
            @RequestParam(defaultValue = "MOVIE") String mediaType,
            @RequestParam(required = false) String metadataStatus,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "36") int size,
            @RequestParam(defaultValue = "updatedAt,desc") String sort
    ) {
        return ApiResponse.success(movieLibraryService.libraryPage(
                currentUserContext.requireCurrentUserId(),
                mediaType,
                metadataStatus,
                page,
                size,
                sort
        ));
    }

    @Operation(summary = "获取最近添加", description = "返回最近添加到视频库的视频列表")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/video/recent")
    ApiResponse<List<MovieVideoItemDto>> recent(@RequestParam(defaultValue = "30") int days) {
        return ApiResponse.success(movieLibraryService.recent(currentUserContext.requireCurrentUserId(), days));
    }

    @Operation(summary = "获取继续观看列表", description = "返回用户未看完的视频列表")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/video/continue")
    ApiResponse<List<MovieContinueWatchingDto>> continueWatching() {
        return ApiResponse.success(movieLibraryService.continueWatching(currentUserContext.requireCurrentUserId()));
    }

    @Operation(summary = "获取收藏视频", description = "返回用户收藏的所有视频")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/video/favorites")
    ApiResponse<List<MovieVideoItemDto>> favorites() {
        return ApiResponse.success(movieEngagementService.favorites(currentUserContext.requireCurrentUserId()));
    }

    @Operation(summary = "获取收藏系列", description = "返回用户收藏的剧集与动漫，按收藏时间倒序")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/video/favorites/series")
    ApiResponse<List<MovieSeriesDto>> favoriteSeries() {
        return ApiResponse.success(movieLibraryService.favoriteSeries(currentUserContext.requireCurrentUserId()));
    }

    @Operation(summary = "获取收藏状态", description = "查询指定视频的收藏状态")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/video/items/{videoItemId}/favorite/status")
    ApiResponse<MovieFavoriteStateDto> favoriteStatus(@PathVariable UUID videoItemId) {
        return ApiResponse.success(movieEngagementService.favoriteStatus(currentUserContext.requireCurrentUserId(), videoItemId));
    }

    @Operation(summary = "收藏/取消收藏视频", description = "切换指定视频的收藏状态")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    @PutMapping("/api/v1/video/items/{videoItemId}/favorite")
    ApiResponse<MovieFavoriteStateDto> favorite(
            @PathVariable UUID videoItemId,
            @RequestParam(defaultValue = "true") boolean favorite
    ) {
        return ApiResponse.success(movieEngagementService.favorite(currentUserContext.requireCurrentUserId(), videoItemId, favorite));
    }

    @Operation(summary = "获取观看历史", description = "返回用户的视频观看历史记录")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/video/history")
    ApiResponse<List<MovieWatchHistoryDto>> history() {
        return ApiResponse.success(movieEngagementService.history(currentUserContext.requireCurrentUserId()));
    }

    @Operation(summary = "删除观看记录", description = "删除指定的观看历史记录")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    @DeleteMapping("/api/v1/video/history/{historyId}")
    ApiResponse<Void> deleteHistoryItem(@PathVariable UUID historyId) {
        movieEngagementService.deleteHistoryItem(currentUserContext.requireCurrentUserId(), historyId);
        return ApiResponse.success();
    }

    @Operation(summary = "清空观看历史", description = "清空用户的全部观看历史记录")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    @DeleteMapping("/api/v1/video/history")
    ApiResponse<Void> clearHistory() {
        movieEngagementService.clearHistory(currentUserContext.requireCurrentUserId());
        return ApiResponse.success();
    }

    @Operation(summary = "获取剧集列表", description = "返回指定剧集的所有分集")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/video/series/{seriesId}/episodes")
    ApiResponse<List<MovieVideoItemDto>> seriesEpisodes(@PathVariable UUID seriesId) {
        return ApiResponse.success(movieLibraryService.episodes(currentUserContext.requireCurrentUserId(), seriesId));
    }

    @Operation(summary = "按类型获取剧集", description = "按类型（TV、动漫等）返回剧集列表")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/video/series/by-type")
    ApiResponse<List<MovieSeriesDto>> seriesByType(
            @RequestParam(defaultValue = "TV") String seriesType) {
        return ApiResponse.success(movieLibraryService.seriesByType(currentUserContext.requireCurrentUserId(), seriesType));
    }

    @Operation(summary = "获取剧集详情", description = "返回指定剧集的详细信息")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/video/series/{seriesId}")
    ApiResponse<MovieSeriesDetailDto> seriesDetail(@PathVariable UUID seriesId) {
        return ApiResponse.success(movieLibraryService.seriesDetail(currentUserContext.requireCurrentUserId(), seriesId));
    }

    @Operation(summary = "更新剧集元数据", description = "手动更新剧集的标题与简介")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    @PutMapping("/api/v1/admin/video/series/{seriesId}/metadata")
    ApiResponse<MovieSeriesDto> updateSeriesMetadata(
            @PathVariable UUID seriesId,
            @Valid @RequestBody UpdateSeriesMetadataRequest request
    ) {
        return ApiResponse.success(movieLibraryService.updateSeriesMetadata(
                currentUserContext.requireCurrentUserId(),
                seriesId,
                request
        ));
    }

    @Operation(summary = "获取季详情", description = "返回指定剧集的指定季详细信息")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/video/series/{seriesId}/seasons/{seasonNumber}")
    ApiResponse<MovieSeasonDetailDto> seasonDetail(
            @PathVariable UUID seriesId,
            @PathVariable int seasonNumber
    ) {
        return ApiResponse.success(movieLibraryService.seasonDetail(currentUserContext.requireCurrentUserId(), seriesId, seasonNumber));
    }

    @Operation(summary = "获取视频资源列表", description = "返回指定视频的所有内容资源（字幕、音轨等）")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/video/items/{videoItemId}/assets")
    ApiResponse<List<MovieContentAssetDto>> itemAssets(@PathVariable UUID videoItemId) {
        return ApiResponse.success(movieLibraryService.itemAssets(currentUserContext.requireCurrentUserId(), videoItemId));
    }

    @Operation(summary = "收藏/取消收藏剧集", description = "切换指定剧集的收藏状态")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    @PostMapping("/api/v1/video/series/{seriesId}/favorite")
    ApiResponse<Map<String, Boolean>> toggleSeriesFavorite(@PathVariable UUID seriesId) {
        boolean favorite = movieEngagementService.toggleSeriesFavorite(currentUserContext.requireCurrentUserId(), seriesId);
        return ApiResponse.success(Map.of("favorite", favorite));
    }

    @Operation(summary = "获取剧集收藏状态", description = "查询指定剧集的收藏状态")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/video/series/{seriesId}/favorite/status")
    ApiResponse<Map<String, Boolean>> seriesFavoriteStatus(@PathVariable UUID seriesId) {
        boolean favorite = movieEngagementService.seriesFavoriteStatus(currentUserContext.requireCurrentUserId(), seriesId);
        return ApiResponse.success(Map.of("favorite", favorite));
    }

    @Operation(summary = "获取合集列表", description = "返回用户的所有视频合集")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/video/collections")
    ApiResponse<List<MovieCollectionDto>> collections() {
        return ApiResponse.success(movieEngagementService.collections(currentUserContext.requireCurrentUserId()));
    }

    @Operation(summary = "创建合集", description = "创建一个新的视频合集")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    @PostMapping("/api/v1/video/collections")
    ApiResponse<MovieCollectionDto> createCollection(@Valid @RequestBody MovieCollectionRequest request) {
        return ApiResponse.success(movieEngagementService.createCollection(currentUserContext.requireCurrentUserId(), request));
    }

    @Operation(summary = "获取合集内容", description = "返回指定合集中的所有视频")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/video/collections/{collectionId}/items")
    ApiResponse<List<MovieVideoItemDto>> collectionItems(@PathVariable UUID collectionId) {
        return ApiResponse.success(movieEngagementService.collectionItems(currentUserContext.requireCurrentUserId(), collectionId));
    }

    @Operation(summary = "添加视频到合集", description = "向指定合集中添加视频")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    @PostMapping("/api/v1/video/collections/{collectionId}/items")
    ApiResponse<MovieCollectionDto> addCollectionItem(
            @PathVariable UUID collectionId,
            @Valid @RequestBody MovieCollectionItemRequest request
    ) {
        return ApiResponse.success(movieEngagementService.addCollectionItem(
                currentUserContext.requireCurrentUserId(),
                collectionId,
                request
        ));
    }

    @Operation(summary = "删除合集", description = "删除指定的视频合集")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    @DeleteMapping("/api/v1/video/collections/{collectionId}")
    ApiResponse<Void> deleteCollection(@PathVariable UUID collectionId) {
        movieEngagementService.deleteCollection(currentUserContext.requireCurrentUserId(), collectionId);
        return ApiResponse.success();
    }

    @Operation(summary = "从合集移除视频", description = "从指定合集中移除视频")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    @DeleteMapping("/api/v1/video/collections/{collectionId}/items/{videoItemId}")
    ApiResponse<Void> removeCollectionItem(
            @PathVariable UUID collectionId,
            @PathVariable UUID videoItemId
    ) {
        movieEngagementService.removeCollectionItem(currentUserContext.requireCurrentUserId(), collectionId, videoItemId);
        return ApiResponse.success();
    }

    @Operation(summary = "获取视频详情", description = "返回指定视频的详细信息")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/video/items/{videoItemId}")
    ApiResponse<MovieVideoItemDto> detail(@PathVariable UUID videoItemId) {
        return ApiResponse.success(movieLibraryService.detail(currentUserContext.requireCurrentUserId(), videoItemId));
    }

    @Operation(summary = "获取视频版本列表", description = "返回指定视频的所有版本（不同清晰度等）")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/video/items/{videoItemId}/versions")
    ApiResponse<List<MovieVideoItemDto>> versions(@PathVariable UUID videoItemId) {
        return ApiResponse.success(movieLibraryService.versions(currentUserContext.requireCurrentUserId(), videoItemId));
    }

    @Operation(summary = "删除视频", description = "删除指定的视频资源")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    @DeleteMapping("/api/v1/video/items/{videoItemId}")
    ApiResponse<FilePurgeTaskDto> deleteItem(
            @PathVariable UUID videoItemId,
            @RequestParam(defaultValue = "false") boolean cascade
    ) {
        UUID taskId = movieLibraryService.deleteItem(
                currentUserContext.requireCurrentUserId(),
                videoItemId,
                cascade
        );
        return ApiResponse.success(FilePurgeTaskDto.queued(taskId));
    }

    @Operation(summary = "获取播放计划", description = "返回指定视频的播放 URL 和元数据")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/video/items/{videoItemId}/playback")
    ApiResponse<PlaybackPlanDto> playbackPlan(@PathVariable UUID videoItemId) {
        return ApiResponse.success(moviePlaybackService.playbackPlan(currentUserContext.requireCurrentUserId(), videoItemId));
    }

    @Operation(summary = "更新播放进度", description = "更新指定视频的播放进度")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    @PutMapping("/api/v1/video/items/{videoItemId}/progress")
    ApiResponse<PlaybackPlanDto> updateProgress(
            @PathVariable UUID videoItemId,
            @Valid @RequestBody PlaybackProgressRequest request
    ) {
        return ApiResponse.success(moviePlaybackService.updateProgress(currentUserContext.requireCurrentUserId(), videoItemId, request));
    }

    @Operation(summary = "获取字幕列表", description = "返回指定视频的所有字幕轨道")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/video/items/{videoItemId}/subtitles")
    ApiResponse<List<SubtitleTrackDto>> listSubtitles(@PathVariable UUID videoItemId) {
        return ApiResponse.success(subtitleManagementService.list(currentUserContext.requireCurrentUserId(), videoItemId));
    }

    @Operation(summary = "上传字幕", description = "为指定视频上传字幕文件")
    @PostMapping("/api/v1/video/items/{videoItemId}/subtitles")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    ApiResponse<SubtitleTrackDto> uploadSubtitle(
            @PathVariable UUID videoItemId,
            @Valid @RequestBody SubtitleUploadRequest request
    ) {
        return ApiResponse.success(subtitleManagementService.upload(currentUserContext.requireCurrentUserId(), videoItemId, request));
    }

    @Operation(summary = "更新字幕", description = "更新指定字幕的内容或语言信息")
    @PutMapping("/api/v1/video/subtitles/{subtitleId}")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    ApiResponse<SubtitleTrackDto> updateSubtitle(
            @PathVariable UUID subtitleId,
            @Valid @RequestBody SubtitleUpdateRequest request
    ) {
        return ApiResponse.success(subtitleManagementService.update(currentUserContext.requireCurrentUserId(), subtitleId, request));
    }

    @Operation(summary = "删除字幕", description = "删除指定的字幕轨道")
    @DeleteMapping("/api/v1/video/subtitles/{subtitleId}")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    ApiResponse<Void> deleteSubtitle(@PathVariable UUID subtitleId) {
        subtitleManagementService.delete(currentUserContext.requireCurrentUserId(), subtitleId);
        return ApiResponse.success();
    }

    @Operation(summary = "获取字幕内容", description = "返回指定字幕的纯文本内容")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/video/subtitles/{subtitleId}/content")
    void subtitleContent(@PathVariable UUID subtitleId, HttpServletResponse response) throws IOException {
        String content = moviePlaybackService.getSubtitleContent(
                currentUserContext.requireCurrentUserId(), subtitleId);
        response.setContentType("text/plain; charset=utf-8");
        response.getWriter().write(content);
    }

    @Operation(summary = "获取刮削候选", description = "从 TMDB 获取指定文件的元数据候选")
    @GetMapping("/api/v1/video/scrape/candidates")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    ApiResponse<List<ScrapeCandidateDto>> scrapeCandidates(@RequestParam UUID fileNodeId) {
        return ApiResponse.success(movieScrapeService.candidates(currentUserContext.requireCurrentUserId(), fileNodeId));
    }

    @Operation(summary = "创建刮削任务", description = "为指定文件创建 TMDB 元数据刮削任务")
    @PostMapping("/api/v1/video/scrape/tasks")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    ApiResponse<ScrapeTaskDto> createScrapeTask(@Valid @RequestBody ScrapeRequest request) {
        return ApiResponse.success(movieScrapeService.createScrapeTask(
                currentUserContext.requireCurrentUserId(),
                request.fileNodeId(),
                request.force()
        ));
    }

    @Operation(summary = "探测视频信息", description = "对指定视频执行 FFprobe 探测，更新媒体信息")
    @PostMapping("/api/v1/video/items/{videoItemId}/probe")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    ApiResponse<Boolean> probeItem(@PathVariable UUID videoItemId) {
        videoProbeService.probeByVideoItemId(currentUserContext.requireCurrentUserId(), videoItemId);
        return ApiResponse.success(true);
    }

    @Operation(summary = "预览 NFO", description = "预览指定视频的 NFO 元数据导出内容")
    @GetMapping("/api/v1/video/items/{videoItemId}/nfo")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    ApiResponse<NfoExportDto> nfoPreview(@PathVariable UUID videoItemId) {
        return ApiResponse.success(movieNfoService.preview(currentUserContext.requireCurrentUserId(), videoItemId));
    }

    @Operation(summary = "导出 NFO", description = "将指定视频的元数据导出为 NFO 文件")
    @PostMapping("/api/v1/video/items/{videoItemId}/nfo")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    ApiResponse<NfoExportDto> exportNfo(@PathVariable UUID videoItemId) {
        return ApiResponse.success(movieNfoService.export(currentUserContext.requireCurrentUserId(), videoItemId));
    }

    @Operation(summary = "获取任务列表", description = "返回用户的视频相关任务列表（转码、刮削等）")
    @GetMapping("/api/v1/video/tasks")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    ApiResponse<List<MovieTaskDto>> tasks(@RequestParam(required = false) String type) {
        return ApiResponse.success(movieTaskService.list(currentUserContext.requireCurrentUserId(), type));
    }

    @Operation(summary = "创建转码任务", description = "为指定视频创建转码任务，支持仅音频转码模式")
    @PostMapping("/api/v1/video/items/{videoItemId}/transcode/tasks")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    ApiResponse<ScrapeTaskDto> createTranscodeTask(
            @PathVariable UUID videoItemId,
            @RequestParam(defaultValue = "false") boolean audioOnly) {
        return ApiResponse.success(movieTaskService.createTranscodeTask(
                currentUserContext.requireCurrentUserId(), videoItemId, audioOnly));
    }

    @Operation(summary = "扫描视频库", description = "触发视频库扫描，检测新增或变更的视频文件")
    @PostMapping("/api/v1/video/scan/tasks")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    ApiResponse<ScrapeTaskDto> scanLibrary(@Valid @RequestBody MovieScanRequest request) {
        return ApiResponse.success(movieTaskService.scanLibrary(currentUserContext.requireCurrentUserId(), request));
    }

    @Operation(summary = "更新视频元数据", description = "手动更新视频的标题、年份、简介等元数据")
    @PutMapping("/api/v1/admin/video/items/{videoItemId}/metadata")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    ApiResponse<MovieVideoItemDto> updateMetadata(
            @PathVariable UUID videoItemId,
            @Valid @RequestBody MovieMetadataUpdateRequest request
    ) {
        return ApiResponse.success(movieLibraryService.updateMetadata(
                currentUserContext.requireCurrentUserId(),
                videoItemId,
                request
        ));
    }
}
