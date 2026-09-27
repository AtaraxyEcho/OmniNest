package com.omninest.modules.video.controller;

import com.omninest.common.api.ApiResponse;
import com.omninest.common.api.PageResponse;
import com.omninest.common.security.CurrentUserContext;
import com.omninest.common.security.Permissions;
import com.omninest.modules.video.dto.MediaLibraryAccessDtos.MediaLibraryAccessDto;
import com.omninest.modules.video.dto.MediaLibraryAccessDtos.UpdateMediaLibraryAccessRequest;
import com.omninest.modules.video.dto.MediaScanDtos.ApplySelectionRequest;
import com.omninest.modules.video.dto.MediaScanDtos.MediaScanRunDto;
import com.omninest.modules.video.dto.MediaScanDtos.MediaScanTreeNodeDto;
import com.omninest.modules.video.dto.MediaScanDtos.SelectionSummaryDto;
import com.omninest.modules.video.dto.MediaScanDtos.UpdateSelectionRequest;
import com.omninest.modules.video.dto.MediaScanDtos.UnavailableMediaDto;
import com.omninest.modules.video.dto.MovieDtos.ScrapeTaskDto;
import com.omninest.modules.video.dto.VideoLibrarySourceDtos.CreateVideoLibrarySourceRequest;
import com.omninest.modules.video.dto.VideoLibrarySourceDtos.MountLibraryProvisionDto;
import com.omninest.modules.video.dto.VideoLibrarySourceDtos.MountLibraryProvisionRequest;
import com.omninest.modules.video.dto.VideoLibrarySourceDtos.UpdateVideoLibrarySourceRequest;
import com.omninest.modules.video.dto.VideoLibrarySourceDtos.VideoLibrarySourceDto;
import com.omninest.modules.video.service.MediaLibraryAccessService;
import com.omninest.modules.video.service.MediaLibraryReviewService;
import com.omninest.modules.video.service.VideoLibrarySourceService;
import com.omninest.modules.user.dto.UserDirectoryDtos.UserDirectoryEntry;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import java.util.List;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * 影视库本地来源管理接口。
 *
 * @author OmniNest
 */
@RestController
@RequiredArgsConstructor
@Tag(name = "影视库来源", description = "本地只读影视目录配置与扫描")
public class VideoLibrarySourceController {

    private final VideoLibrarySourceService sourceService;
    private final MediaLibraryReviewService reviewService;
    private final MediaLibraryAccessService accessService;
    private final CurrentUserContext currentUserContext;

    @Operation(summary = "列出影视库来源")
    @GetMapping("/api/v1/video/library-sources")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_LIBRARY_MANAGE + "')")
    ApiResponse<List<VideoLibrarySourceDto>> list() {
        return ApiResponse.success(sourceService.list(currentUserContext.requireCurrentUserId()));
    }

    @Operation(summary = "创建影视库来源")
    @PostMapping("/api/v1/video/library-sources")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_LIBRARY_MANAGE + "')")
    ApiResponse<VideoLibrarySourceDto> create(@Valid @RequestBody CreateVideoLibrarySourceRequest request) {
        return ApiResponse.success(sourceService.create(currentUserContext.requireCurrentUserId(), request));
    }

    @Operation(
            summary = "挂载媒体库一键开通",
            description = "按约定目录 Movie/TV/Anime 维护三个类型库源，仅需启用与自动入库开关"
    )
    @PostMapping("/api/v1/video/library-sources/mount-provision")
    @PreAuthorize(
            "hasAuthority('" + Permissions.MEDIA_LIBRARY_MANAGE + "')"
                    + " and hasAuthority('" + Permissions.SYSTEM_CONFIG_MANAGE + "')"
    )
    ApiResponse<MountLibraryProvisionDto> provisionMountLibrary(
            @Valid @RequestBody MountLibraryProvisionRequest request
    ) {
        return ApiResponse.success(
                sourceService.provisionMountLibrary(currentUserContext.requireCurrentUserId(), request)
        );
    }

    @Operation(summary = "更新影视库来源")
    @PutMapping("/api/v1/video/library-sources/{sourceId}")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_LIBRARY_MANAGE + "')")
    ApiResponse<VideoLibrarySourceDto> update(
            @PathVariable UUID sourceId,
            @Valid @RequestBody UpdateVideoLibrarySourceRequest request
    ) {
        return ApiResponse.success(sourceService.update(
                currentUserContext.requireCurrentUserId(),
                sourceId,
                request
        ));
    }

    @Operation(summary = "扫描影视库来源")
    @PostMapping("/api/v1/video/library-sources/{sourceId}/scan/tasks")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_LIBRARY_MANAGE + "')")
    ApiResponse<ScrapeTaskDto> scan(@PathVariable UUID sourceId) {
        return ApiResponse.success(sourceService.scan(currentUserContext.requireCurrentUserId(), sourceId));
    }

    @Operation(summary = "发现影视库候选")
    @PostMapping("/api/v1/video/library-sources/{sourceId}/discovery/tasks")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_LIBRARY_MANAGE + "')")
    ApiResponse<ScrapeTaskDto> discover(@PathVariable UUID sourceId) {
        return ApiResponse.success(sourceService.scan(currentUserContext.requireCurrentUserId(), sourceId));
    }

    @Operation(summary = "查询来源最近一次发现运行")
    @GetMapping("/api/v1/video/library-sources/{sourceId}/scan-runs/latest")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_LIBRARY_MANAGE + "')")
    ApiResponse<MediaScanRunDto> latestRun(@PathVariable UUID sourceId) {
        return ApiResponse.success(reviewService.latestRun(currentUserContext.requireCurrentUserId(), sourceId));
    }

    @Operation(summary = "查询媒体发现运行")
    @GetMapping("/api/v1/video/scan-runs/{runId}")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_LIBRARY_MANAGE + "')")
    ApiResponse<MediaScanRunDto> getRun(@PathVariable UUID runId) {
        return ApiResponse.success(reviewService.getRun(currentUserContext.requireCurrentUserId(), runId));
    }

    @Operation(summary = "懒加载候选媒体语义树")
    @GetMapping("/api/v1/video/scan-runs/{runId}/tree")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_LIBRARY_MANAGE + "')")
    ApiResponse<PageResponse<MediaScanTreeNodeDto>> tree(
            @PathVariable UUID runId,
            @RequestParam(required = false) String parentNodeId,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "100") int size
    ) {
        return ApiResponse.success(reviewService.tree(
                currentUserContext.requireCurrentUserId(),
                runId,
                parentNodeId,
                page,
                size
        ));
    }

    @Operation(summary = "更新候选选择范围")
    @PostMapping("/api/v1/video/scan-runs/{runId}/selection-rules")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_LIBRARY_MANAGE + "')")
    ApiResponse<SelectionSummaryDto> updateSelection(
            @PathVariable UUID runId,
            @Valid @RequestBody UpdateSelectionRequest request
    ) {
        return ApiResponse.success(reviewService.updateSelection(
                currentUserContext.requireCurrentUserId(),
                runId,
                request
        ));
    }

    @Operation(summary = "查询候选选择汇总")
    @GetMapping("/api/v1/video/scan-runs/{runId}/selection-summary")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_LIBRARY_MANAGE + "')")
    ApiResponse<SelectionSummaryDto> selectionSummary(@PathVariable UUID runId) {
        return ApiResponse.success(reviewService.summary(currentUserContext.requireCurrentUserId(), runId));
    }

    @Operation(summary = "将所选候选分批加入媒体库")
    @PostMapping("/api/v1/video/scan-runs/{runId}/apply/tasks")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_LIBRARY_MANAGE + "')")
    ApiResponse<ScrapeTaskDto> apply(
            @PathVariable UUID runId,
            @Valid @RequestBody ApplySelectionRequest request
    ) {
        return ApiResponse.success(reviewService.apply(
                currentUserContext.requireCurrentUserId(),
                runId,
                request
        ));
    }

    @Operation(summary = "暂停候选入库")
    @PostMapping("/api/v1/video/scan-runs/{runId}/pause")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_LIBRARY_MANAGE + "')")
    ApiResponse<MediaScanRunDto> pause(@PathVariable UUID runId) {
        return ApiResponse.success(reviewService.pause(currentUserContext.requireCurrentUserId(), runId));
    }

    @Operation(summary = "取消媒体发现或入库运行")
    @PostMapping("/api/v1/video/scan-runs/{runId}/cancel")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_LIBRARY_MANAGE + "')")
    ApiResponse<MediaScanRunDto> cancel(@PathVariable UUID runId) {
        return ApiResponse.success(reviewService.cancel(currentUserContext.requireCurrentUserId(), runId));
    }

    @Operation(summary = "查询不可用本地媒体")
    @GetMapping("/api/v1/video/library-sources/unavailable")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_LIBRARY_MANAGE + "')")
    ApiResponse<PageResponse<UnavailableMediaDto>> unavailable(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "100") int size
    ) {
        return ApiResponse.success(reviewService.unavailable(
                currentUserContext.requireCurrentUserId(),
                page,
                size
        ));
    }

    @Operation(summary = "删除影视库来源")
    @DeleteMapping("/api/v1/video/library-sources/{sourceId}")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_LIBRARY_MANAGE + "')")
    ApiResponse<Void> delete(@PathVariable UUID sourceId) {
        sourceService.delete(currentUserContext.requireCurrentUserId(), sourceId);
        return ApiResponse.success();
    }

    @Operation(summary = "查询媒体库访问设置")
    @GetMapping("/api/v1/video/library-sources/{sourceId}/access")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_LIBRARY_MANAGE + "')")
    ApiResponse<MediaLibraryAccessDto> access(@PathVariable UUID sourceId) {
        return ApiResponse.success(accessService.details(currentUserContext.requireCurrentUserId(), sourceId));
    }

    @Operation(summary = "更新媒体库访问设置")
    @PutMapping("/api/v1/video/library-sources/{sourceId}/access")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_LIBRARY_MANAGE + "')")
    ApiResponse<MediaLibraryAccessDto> updateAccess(
            @PathVariable UUID sourceId,
            @Valid @RequestBody UpdateMediaLibraryAccessRequest request
    ) {
        return ApiResponse.success(accessService.replaceSelectedUsers(
                currentUserContext.requireCurrentUserId(),
                sourceId,
                request
        ));
    }

    @Operation(summary = "搜索媒体库授权用户候选")
    @GetMapping("/api/v1/video/library-access/users")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_LIBRARY_MANAGE + "')")
    ApiResponse<PageResponse<UserDirectoryEntry>> accessUsers(
            @RequestParam(required = false) String query,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "50") int size
    ) {
        return ApiResponse.success(accessService.userCandidates(
                currentUserContext.requireCurrentUserId(),
                query,
                page,
                size
        ));
    }
}
