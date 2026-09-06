package com.omninest.modules.photos.controller;

import com.omninest.common.api.ApiResponse;
import com.omninest.common.api.PageResponse;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.security.CurrentUserContext;
import com.omninest.common.security.Permissions;
import com.omninest.modules.file.dto.FilePurgeTaskDto;
import com.omninest.modules.file.dto.ShareAccessSessionDto;
import com.omninest.modules.file.dto.ShareAuthorizationRequest;
import com.omninest.modules.photos.dto.GroupBy;
import com.omninest.modules.photos.dto.PhotoDtos.AddPhotosToAlbumRequest;
import com.omninest.modules.photos.dto.PhotoDtos.PhotoRelationsDto;
import com.omninest.modules.photos.dto.PhotoDtos.AddTagRequest;
import com.omninest.modules.photos.dto.PhotoDtos.BackupReportRequest;
import com.omninest.modules.photos.dto.PhotoDtos.BackupStatusRequest;
import com.omninest.modules.photos.dto.PhotoDtos.CheckDuplicateRequest;
import com.omninest.modules.photos.dto.PhotoDtos.CreateAlbumRequest;
import com.omninest.modules.photos.dto.PhotoDtos.CreateAlbumShareRequest;
import com.omninest.modules.photos.dto.PhotoDtos.CreateBatchTaskRequest;
import com.omninest.modules.photos.dto.PhotoDtos.DeletePhotosRequest;
import com.omninest.modules.photos.dto.PhotoDtos.EditRequest;
import com.omninest.modules.photos.dto.PhotoDtos.NameClusterRequest;
import com.omninest.modules.photos.dto.PhotoDtos.PhotoAlbumDetailDto;
import com.omninest.modules.photos.dto.PhotoDtos.PhotoAlbumDto;
import com.omninest.modules.photos.dto.PhotoDtos.PhotoAiTaskDto;
import com.omninest.modules.photos.dto.PhotoDtos.PhotoBackupStatusDto;
import com.omninest.modules.photos.dto.PhotoDtos.PhotoBatchDownloadTicketDto;
import com.omninest.modules.photos.dto.PhotoDtos.PhotoBatchTaskDto;
import com.omninest.modules.photos.dto.PhotoDtos.PhotoDashboardDto;
import com.omninest.modules.photos.dto.PhotoDtos.PhotoEditVersionDto;
import com.omninest.modules.photos.dto.PhotoDtos.PhotoFaceClusterDto;
import com.omninest.modules.photos.dto.PhotoDtos.PhotoGroupDto;
import com.omninest.modules.photos.dto.PhotoDtos.PhotoItemDto;
import com.omninest.modules.photos.dto.PhotoDtos.PhotoListItemDto;
import com.omninest.modules.photos.dto.PhotoDtos.PhotoTrashResultDto;
import com.omninest.modules.photos.dto.PhotoDtos.PhotoScanJobDto;
import com.omninest.modules.photos.dto.PhotoDtos.PhotoShareLinkDto;
import com.omninest.modules.photos.dto.PhotoDtos.PhotoSharedAlbumDto;
import com.omninest.modules.photos.dto.PhotoDtos.PhotoTimelineDto;
import com.omninest.modules.photos.dto.PhotoDtos.PhotoTimelineMonthDto;
import com.omninest.modules.photos.service.PhotoAdminService;
import com.omninest.modules.photos.service.PhotoAiService;
import com.omninest.modules.photos.service.PhotoAiTaskService;
import com.omninest.modules.photos.service.PhotoAlbumService;
import com.omninest.modules.photos.service.PhotoBackupService;
import com.omninest.modules.photos.service.PhotoBatchService;
import com.omninest.modules.photos.service.PhotoEditService;
import com.omninest.modules.photos.service.GeoDatasetService;
import com.omninest.modules.photos.service.PhotoLibraryService;
import com.omninest.modules.photos.service.PhotoRelationService;
import com.omninest.modules.photos.service.PhotosRuntimeConfigService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * 照片中心接口控制器，提供浏览、收藏、相册和管理功能。
 *
 * @author OmniNest
 */
@Tag(name = "照片库", description = "照片资源的管理与相册操作")
@RestController
@RequiredArgsConstructor
public class PhotoLibraryController {

    private final PhotoLibraryService libraryService;
    private final PhotoAlbumService albumService;
    private final PhotoAdminService adminService;
    private final PhotoBatchService batchService;
    private final PhotoEditService editService;
    private final GeoDatasetService geoDatasetService;
    private final PhotoBackupService backupService;
    private final PhotoAiService photoAiService;
    private final PhotoAiTaskService photoAiTaskService;
    private final PhotosRuntimeConfigService photosRuntimeConfigService;
    private final PhotoRelationService relationService;
    private final CurrentUserContext currentUserContext;

    // ─── 浏览 ───

    @Operation(summary = "获取照片仪表盘", description = "返回用户的照片概览信息，包括总数、最近添加等")
    @PreAuthorize("hasAuthority('" + Permissions.PHOTO_READ + "')")
    @GetMapping("/api/v1/photos/dashboard")
    ApiResponse<PhotoDashboardDto> dashboard() {
        UUID userId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(libraryService.dashboard(userId));
    }

    @Operation(summary = "获取照片列表", description = "按关键词搜索或返回用户的所有照片")
    @PreAuthorize("hasAuthority('" + Permissions.PHOTO_READ + "')")
    @GetMapping("/api/v1/photos")
    ApiResponse<List<PhotoItemDto>> listPhotos(
            @RequestParam(required = false) String query,
            HttpServletResponse response
    ) {
        UUID userId = currentUserContext.requireCurrentUserId();
        int limit = photosRuntimeConfigService.legacyListLimit();
        markLegacyListEndpoint(response, "/api/v1/photos/page");
        Page<PhotoListItemDto> page = libraryService.listPhotosPage(
                userId,
                0,
                limit,
                "createdAt,desc",
                query
        );
        return ApiResponse.success(page.getContent().stream().map(this::toLegacyPhotoItem).toList());
    }

    @Operation(summary = "分页获取照片列表", description = "按关键词、页码和白名单排序返回照片轻量列表")
    @PreAuthorize("hasAuthority('" + Permissions.PHOTO_READ + "')")
    @GetMapping("/api/v1/photos/page")
    ApiResponse<PageResponse<PhotoListItemDto>> listPhotosPage(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "50") int size,
            @RequestParam(defaultValue = "createdAt,desc") String sort,
            @RequestParam(required = false) String query
    ) {
        UUID userId = currentUserContext.requireCurrentUserId();
        Page<PhotoListItemDto> result = libraryService.listPhotosPage(userId, page, size, sort, query);
        return ApiResponse.success(PageResponse.of(
                result.getContent(),
                result.getNumber(),
                result.getSize(),
                result.getTotalElements()
        ));
    }

    @Operation(summary = "获取照片详情", description = "返回指定照片的详细信息")
    @PreAuthorize("hasAuthority('" + Permissions.PHOTO_READ + "')")
    @GetMapping("/api/v1/photos/{photoId}")
    ApiResponse<PhotoItemDto> photo(@PathVariable UUID photoId) {
        UUID userId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(libraryService.photo(userId, photoId));
    }

    @Operation(summary = "删除照片", description = "将照片移入回收站（保留 30 天，可恢复）")
    @PreAuthorize("hasAuthority('" + Permissions.PHOTO_WRITE + "')")
    @DeleteMapping("/api/v1/photos/{photoId}")
    ApiResponse<Void> deletePhoto(@PathVariable UUID photoId) {
        UUID userId = currentUserContext.requireCurrentUserId();
        libraryService.movePhotoToTrash(userId, photoId);
        return ApiResponse.success(null);
    }

    /**
     * 批量将照片移入回收站。
     *
     * @param body 批量照片请求
     * @return 逐项处理结果
     */
    @Operation(summary = "批量删除照片", description = "将多张照片移入回收站，返回逐项结果")
    @PreAuthorize("hasAuthority('" + Permissions.PHOTO_WRITE + "')")
    @DeleteMapping("/api/v1/photos/batch")
    ApiResponse<List<PhotoTrashResultDto>> deletePhotos(@Valid @RequestBody DeletePhotosRequest body) {
        UUID userId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(libraryService.movePhotosToTrash(userId, body.photoIds()));
    }

    @Operation(summary = "创建 GeoNames 数据集导入任务",
            description = "从服务端共享目录（photo.geo.import.dir，默认 data/geonames）读取 dump 文件，"
                    + "由 Worker 异步导入、验证并发布为当前线上数据集")
    @PreAuthorize("hasAuthority('" + Permissions.PHOTO_ADMIN + "')")
    @PostMapping("/api/v1/admin/photos/geo/import")
    ApiResponse<GeoDatasetService.GeoImportCreated> importGeoDataset(
            @RequestBody GeoDatasetService.GeoImportRequest body
    ) {
        UUID operatorId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(geoDatasetService.createImportTask(body, operatorId));
    }

    @Operation(summary = "重载离线地名索引", description = "将本实例内存索引重载到当前已发布数据集")
    @PreAuthorize("hasAuthority('" + Permissions.PHOTO_ADMIN + "')")
    @PostMapping("/api/v1/admin/photos/geo/reload")
    ApiResponse<Map<String, Object>> reloadGeoIndex() {
        String datasetVersion = geoDatasetService.reloadCurrentPublished();
        Map<String, Object> body = new java.util.LinkedHashMap<>();
        body.put("datasetVersion", datasetVersion);
        return ApiResponse.success(body);
    }

    @Operation(summary = "创建存量照片位置回填任务",
            description = "为有坐标但缺地名的照片创建后台回填任务；已存在活跃回填任务时返回原任务")
    @PreAuthorize("hasAuthority('" + Permissions.PHOTO_ADMIN + "')")
    @PostMapping("/api/v1/admin/photos/geo/backfill")
    ApiResponse<GeoDatasetService.GeoBackfillCreated> backfillGeocode(
            @RequestParam(required = false) Integer batchSize
    ) {
        UUID operatorId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(geoDatasetService.createBackfillTask(operatorId, batchSize));
    }

    @Operation(summary = "保存外部编辑结果", description = "接收编辑器产出的整图字节并存为新编辑版本")
    @PreAuthorize("hasAuthority('" + Permissions.PHOTO_WRITE + "')")
    @PostMapping(value = "/api/v1/photos/{photoId}/edited-image", consumes = "image/jpeg")
    ApiResponse<PhotoEditVersionDto> applyEditedImage(
            @PathVariable UUID photoId,
            @RequestBody byte[] image
    ) {
        UUID userId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(editService.applyEditedImage(userId, photoId, image));
    }

    @Operation(summary = "按标签查询照片", description = "返回携带指定标签的照片列表")
    @PreAuthorize("hasAuthority('" + Permissions.PHOTO_READ + "')")
    @GetMapping("/api/v1/photos/by-tag")
    ApiResponse<List<PhotoItemDto>> listByTag(@RequestParam String tag) {
        UUID userId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(libraryService.listByTag(userId, tag));
    }

    // ─── 回收站 ───

    @Operation(summary = "回收站照片列表", description = "分页查询回收站中的照片")
    @PreAuthorize("hasAuthority('" + Permissions.PHOTO_READ + "')")
    @GetMapping("/api/v1/photos/trash/page")
    ApiResponse<PageResponse<PhotoListItemDto>> trashPage(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "50") int size
    ) {
        UUID userId = currentUserContext.requireCurrentUserId();
        Page<PhotoListItemDto> result = libraryService.listTrashPage(userId, page, size);
        return ApiResponse.success(PageResponse.of(
                result.getContent(),
                result.getNumber(),
                result.getSize(),
                result.getTotalElements()
        ));
    }

    @Operation(summary = "恢复回收站照片", description = "将照片从回收站恢复为正常状态")
    @PreAuthorize("hasAuthority('" + Permissions.PHOTO_WRITE + "')")
    @PostMapping("/api/v1/photos/{photoId}/restore")
    ApiResponse<Void> restorePhoto(@PathVariable UUID photoId) {
        UUID userId = currentUserContext.requireCurrentUserId();
        libraryService.restorePhotoFromTrash(userId, photoId);
        return ApiResponse.success(null);
    }

    @Operation(summary = "永久删除照片", description = "对回收站中的照片创建永久删除任务")
    @PreAuthorize("hasAuthority('" + Permissions.PHOTO_WRITE + "')")
    @DeleteMapping("/api/v1/photos/{photoId}/purge")
    ApiResponse<FilePurgeTaskDto> purgePhoto(
            @PathVariable UUID photoId,
            @RequestParam(defaultValue = "false") boolean cascade
    ) {
        UUID userId = currentUserContext.requireCurrentUserId();
        UUID taskId = libraryService.purgePhotoFromTrash(userId, photoId, cascade);
        return ApiResponse.success(FilePurgeTaskDto.queued(taskId));
    }

    @Operation(summary = "清空回收站", description = "对回收站内全部照片创建批量永久删除任务")
    @PreAuthorize("hasAuthority('" + Permissions.PHOTO_WRITE + "')")
    @PostMapping("/api/v1/photos/trash/purge")
    ApiResponse<FilePurgeTaskDto> purgeTrash() {
        UUID userId = currentUserContext.requireCurrentUserId();
        UUID taskId = libraryService.purgeTrash(userId);
        return ApiResponse.success(FilePurgeTaskDto.queued(taskId));
    }

    @Operation(summary = "补充位置地名", description = "对有 GPS 坐标但缺少地名的照片重新执行逆地理编码")
    @PreAuthorize("hasAuthority('" + Permissions.PHOTO_WRITE + "')")
    @PostMapping("/api/v1/photos/{photoId}/geocode")
    ApiResponse<Void> backfillGeocode(@PathVariable UUID photoId) {
        UUID userId = currentUserContext.requireCurrentUserId();
        libraryService.backfillPhotoGeocode(userId, photoId);
        return ApiResponse.success(null);
    }

    // ─── 收藏 ───

    @Operation(summary = "获取收藏照片", description = "返回用户收藏的所有照片")
    @PreAuthorize("hasAuthority('" + Permissions.PHOTO_READ + "')")
    @GetMapping("/api/v1/photos/favorites")
    ApiResponse<List<PhotoItemDto>> listFavorites(HttpServletResponse response) {
        UUID userId = currentUserContext.requireCurrentUserId();
        int limit = photosRuntimeConfigService.legacyListLimit();
        markLegacyListEndpoint(response, "/api/v1/photos/favorites/page");
        Page<PhotoListItemDto> page = libraryService.listFavoritesPage(
                userId,
                0,
                limit,
                "createdAt,desc",
                null
        );
        return ApiResponse.success(page.getContent().stream().map(this::toLegacyPhotoItem).toList());
    }

    @Operation(summary = "分页获取收藏照片", description = "按关键词、页码和白名单排序返回收藏照片轻量列表")
    @PreAuthorize("hasAuthority('" + Permissions.PHOTO_READ + "')")
    @GetMapping("/api/v1/photos/favorites/page")
    ApiResponse<PageResponse<PhotoListItemDto>> listFavoritesPage(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "50") int size,
            @RequestParam(defaultValue = "createdAt,desc") String sort,
            @RequestParam(required = false) String query
    ) {
        UUID userId = currentUserContext.requireCurrentUserId();
        Page<PhotoListItemDto> result = libraryService.listFavoritesPage(userId, page, size, sort, query);
        return ApiResponse.success(PageResponse.of(
                result.getContent(),
                result.getNumber(),
                result.getSize(),
                result.getTotalElements()
        ));
    }

    @Operation(summary = "收藏照片", description = "将指定照片添加到收藏")
    @PreAuthorize("hasAuthority('" + Permissions.PHOTO_WRITE + "')")
    @PostMapping("/api/v1/photos/{photoId}/favorite")
    ApiResponse<Void> addFavorite(@PathVariable UUID photoId) {
        UUID userId = currentUserContext.requireCurrentUserId();
        libraryService.addFavorite(userId, photoId);
        return ApiResponse.success();
    }

    @Operation(summary = "取消收藏照片", description = "将指定照片从收藏中移除")
    @PreAuthorize("hasAuthority('" + Permissions.PHOTO_WRITE + "')")
    @DeleteMapping("/api/v1/photos/{photoId}/favorite")
    ApiResponse<Void> removeFavorite(@PathVariable UUID photoId) {
        UUID userId = currentUserContext.requireCurrentUserId();
        libraryService.removeFavorite(userId, photoId);
        return ApiResponse.success();
    }

    // ─── 相册 ───

    @Operation(summary = "获取相册列表", description = "返回用户的所有相册")
    @PreAuthorize("hasAuthority('" + Permissions.PHOTO_READ + "')")
    @GetMapping("/api/v1/photos/albums")
    ApiResponse<List<PhotoAlbumDto>> listAlbums() {
        UUID userId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(albumService.listAlbums(userId));
    }

    @Operation(summary = "创建相册", description = "创建一个新的照片相册")
    @PreAuthorize("hasAuthority('" + Permissions.PHOTO_WRITE + "')")
    @PostMapping("/api/v1/photos/albums")
    ApiResponse<PhotoAlbumDto> createAlbum(@Valid @RequestBody CreateAlbumRequest body) {
        UUID userId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(albumService.createAlbum(userId, body));
    }

    @Operation(summary = "更新相册", description = "更新指定相册的名称或描述")
    @PreAuthorize("hasAuthority('" + Permissions.PHOTO_WRITE + "')")
    @PutMapping("/api/v1/photos/albums/{albumId}")
    ApiResponse<PhotoAlbumDto> updateAlbum(
            @PathVariable UUID albumId,
            @Valid @RequestBody CreateAlbumRequest body
    ) {
        UUID userId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(albumService.updateAlbum(userId, albumId, body));
    }

    @Operation(summary = "删除相册", description = "删除指定的照片相册")
    @PreAuthorize("hasAuthority('" + Permissions.PHOTO_WRITE + "')")
    @DeleteMapping("/api/v1/photos/albums/{albumId}")
    ApiResponse<Void> deleteAlbum(@PathVariable UUID albumId) {
        UUID userId = currentUserContext.requireCurrentUserId();
        albumService.deleteAlbum(userId, albumId);
        return ApiResponse.success();
    }

    @Operation(summary = "获取相册详情", description = "返回指定相册的详细信息及其包含的照片")
    @PreAuthorize("hasAuthority('" + Permissions.PHOTO_READ + "')")
    @GetMapping("/api/v1/photos/albums/{albumId}")
    ApiResponse<PhotoAlbumDetailDto> albumDetail(@PathVariable UUID albumId) {
        UUID userId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(albumService.albumDetail(userId, albumId));
    }

    @Operation(summary = "添加照片到相册", description = "向指定相册中添加照片")
    @PreAuthorize("hasAuthority('" + Permissions.PHOTO_WRITE + "')")
    @PostMapping("/api/v1/photos/albums/{albumId}/items")
    ApiResponse<Void> addPhotosToAlbum(
            @PathVariable UUID albumId,
            @Valid @RequestBody AddPhotosToAlbumRequest body
    ) {
        UUID userId = currentUserContext.requireCurrentUserId();
        albumService.addPhotos(userId, albumId, body.photoIds());
        return ApiResponse.success();
    }

    @Operation(summary = "分页获取相册候选照片", description = "返回可加入相册的照片轻量列表，排除已在该相册内的照片")
    @PreAuthorize("hasAuthority('" + Permissions.PHOTO_READ + "')")
    @GetMapping("/api/v1/photos/albums/{albumId}/candidates/page")
    ApiResponse<PageResponse<PhotoListItemDto>> albumCandidatesPage(
            @PathVariable UUID albumId,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "50") int size,
            @RequestParam(defaultValue = "createdAt,desc") String sort
    ) {
        UUID userId = currentUserContext.requireCurrentUserId();
        Page<PhotoListItemDto> result = libraryService.listAlbumCandidatesPage(
                userId,
                albumId,
                page,
                size,
                sort
        );
        return ApiResponse.success(PageResponse.of(
                result.getContent(),
                result.getNumber(),
                result.getSize(),
                result.getTotalElements()
        ));
    }

    @Operation(summary = "从相册移除照片", description = "从指定相册中移除照片")
    @PreAuthorize("hasAuthority('" + Permissions.PHOTO_WRITE + "')")
    @DeleteMapping("/api/v1/photos/albums/{albumId}/items/{photoId}")
    ApiResponse<Void> removePhotoFromAlbum(
            @PathVariable UUID albumId,
            @PathVariable UUID photoId
    ) {
        UUID userId = currentUserContext.requireCurrentUserId();
        albumService.removePhoto(userId, albumId, photoId);
        return ApiResponse.success();
    }

    // ─── 时间线与分组 ───

    @Operation(summary = "获取照片时间线", description = "按时间分组返回用户的照片时间线")
    @PreAuthorize("hasAuthority('" + Permissions.PHOTO_READ + "')")
    @GetMapping("/api/v1/photos/timeline")
    ApiResponse<PhotoTimelineDto> timeline(HttpServletResponse response) {
        UUID userId = currentUserContext.requireCurrentUserId();
        markLegacyListEndpoint(response, "/api/v1/photos/timeline/page");
        return ApiResponse.success(libraryService.timeline(
                userId,
                photosRuntimeConfigService.legacyListLimit()
        ));
    }

    @Operation(summary = "分页获取照片时间线", description = "按年月分页返回计数和每月最多四张轻量预览")
    @PreAuthorize("hasAuthority('" + Permissions.PHOTO_READ + "')")
    @GetMapping("/api/v1/photos/timeline/page")
    ApiResponse<PageResponse<PhotoTimelineMonthDto>> timelinePage(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "50") int size
    ) {
        UUID userId = currentUserContext.requireCurrentUserId();
        Page<PhotoTimelineMonthDto> result = libraryService.timelinePage(userId, page, size);
        return ApiResponse.success(PageResponse.of(
                result.getContent(),
                result.getNumber(),
                result.getSize(),
                result.getTotalElements()
        ));
    }

    @Operation(summary = "分页获取指定年月的照片", description = "按年月区间返回照片轻量列表，时间口径与时间线一致")
    @PreAuthorize("hasAuthority('" + Permissions.PHOTO_READ + "')")
    @GetMapping("/api/v1/photos/period/page")
    ApiResponse<PageResponse<PhotoListItemDto>> periodPage(
            @RequestParam int year,
            @RequestParam int month,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "50") int size,
            @RequestParam(defaultValue = "dateTaken,desc") String sort
    ) {
        UUID userId = currentUserContext.requireCurrentUserId();
        Page<PhotoListItemDto> result = libraryService.listPeriodPage(userId, year, month, page, size, sort);
        return ApiResponse.success(PageResponse.of(
                result.getContent(),
                result.getNumber(),
                result.getSize(),
                result.getTotalElements()
        ));
    }

    @Operation(summary = "获取照片分组", description = "按指定维度（日期、月份、年份等）对照片进行分组")
    @PreAuthorize("hasAuthority('" + Permissions.PHOTO_READ + "')")
    @GetMapping("/api/v1/photos/groups")
    ApiResponse<List<PhotoGroupDto>> groups(
            @RequestParam GroupBy by,
            HttpServletResponse response
    ) {
        UUID userId = currentUserContext.requireCurrentUserId();
        markLegacyListEndpoint(response, "/api/v1/photos/groups/page");
        return ApiResponse.success(libraryService.groupBy(
                userId,
                by,
                photosRuntimeConfigService.legacyListLimit()
        ));
    }

    @Operation(summary = "分页获取照片分组", description = "按指定维度分页聚合计数并返回每组最多四张预览")
    @PreAuthorize("hasAuthority('" + Permissions.PHOTO_READ + "')")
    @GetMapping("/api/v1/photos/groups/page")
    ApiResponse<PageResponse<PhotoGroupDto>> groupsPage(
            @RequestParam GroupBy by,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "50") int size
    ) {
        UUID userId = currentUserContext.requireCurrentUserId();
        Page<PhotoGroupDto> result = libraryService.groupByPage(userId, by, page, size);
        return ApiResponse.success(PageResponse.of(
                result.getContent(),
                result.getNumber(),
                result.getSize(),
                result.getTotalElements()
        ));
    }

    // ─── 标签 ───

    @Operation(summary = "获取标签列表", description = "返回用户照片中使用的所有标签")
    @PreAuthorize("hasAuthority('" + Permissions.PHOTO_READ + "')")
    @GetMapping("/api/v1/photos/tags")
    ApiResponse<List<String>> listTags() {
        UUID userId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(libraryService.listTags(userId));
    }

    @Operation(summary = "添加标签", description = "为指定照片添加标签")
    @PreAuthorize("hasAuthority('" + Permissions.PHOTO_WRITE + "')")
    @PostMapping("/api/v1/photos/{photoId}/tags")
    ApiResponse<Void> addTag(@PathVariable UUID photoId, @Valid @RequestBody AddTagRequest body) {
        UUID userId = currentUserContext.requireCurrentUserId();
        libraryService.addTag(userId, photoId, body.tag());
        return ApiResponse.success();
    }

    @Operation(summary = "移除标签", description = "从指定照片中移除标签")
    @PreAuthorize("hasAuthority('" + Permissions.PHOTO_WRITE + "')")
    @DeleteMapping("/api/v1/photos/{photoId}/tags/{tag}")
    ApiResponse<Void> removeTag(@PathVariable UUID photoId, @PathVariable String tag) {
        UUID userId = currentUserContext.requireCurrentUserId();
        libraryService.removeTag(userId, photoId, tag);
        return ApiResponse.success();
    }

    // ─── 批量任务 ───

    @Operation(summary = "创建批量任务", description = "创建照片批量操作任务（下载、删除等）")
    @PreAuthorize("hasAuthority('" + Permissions.PHOTO_WRITE + "')")
    @PostMapping("/api/v1/photos/batch")
    ApiResponse<PhotoBatchTaskDto> createBatchTask(@Valid @RequestBody CreateBatchTaskRequest body) {
        UUID userId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(batchService.createBatchTask(userId, body));
    }

    @Operation(summary = "查询批量任务状态", description = "查询指定批量任务的执行状态")
    @PreAuthorize("hasAuthority('" + Permissions.PHOTO_READ + "')")
    @GetMapping("/api/v1/photos/batch/{taskId}")
    ApiResponse<PhotoBatchTaskDto> batchTaskStatus(@PathVariable UUID taskId) {
        UUID userId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(batchService.getTaskStatus(userId, taskId));
    }

    @Operation(summary = "获取批量下载地址", description = "返回批量任务结果的下载地址")
    @PreAuthorize("hasAuthority('" + Permissions.PHOTO_READ + "')")
    @GetMapping("/api/v1/photos/batch/{taskId}/download")
    ApiResponse<Map<String, String>> batchDownloadUrl(@PathVariable UUID taskId) {
        UUID userId = currentUserContext.requireCurrentUserId();
        PhotoBatchTaskDto task = batchService.getTaskStatus(userId, taskId);
        if (task.result() == null || task.result().isBlank()) {
            return ApiResponse.success(Map.of());
        }
        PhotoBatchDownloadTicketDto ticket = batchService.resolveDownloadTicket(userId, taskId);
        return ApiResponse.success(Map.of("url", ticket.url()));
    }

    @Operation(summary = "获取批量下载票据", description = "返回 ZIP 文件名、大小、摘要和短期签名地址")
    @PreAuthorize("hasAuthority('" + Permissions.PHOTO_READ + "')")
    @GetMapping("/api/v1/photos/batch/{taskId}/download-ticket")
    ApiResponse<PhotoBatchDownloadTicketDto> batchDownloadTicket(@PathVariable UUID taskId) {
        UUID userId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(batchService.resolveDownloadTicket(userId, taskId));
    }

    // ─── 编辑 ───

    @Operation(summary = "编辑照片", description = "对指定照片执行编辑操作（裁剪、旋转、滤镜等）")
    @PreAuthorize("hasAuthority('" + Permissions.PHOTO_WRITE + "')")
    @PostMapping("/api/v1/photos/{photoId}/edit")
    ApiResponse<PhotoEditVersionDto> editPhoto(
            @PathVariable UUID photoId,
            @Valid @RequestBody EditRequest body
    ) {
        UUID userId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(editService.applyEdit(userId, photoId, body));
    }

    @Operation(summary = "获取编辑版本列表", description = "返回指定照片的所有编辑版本")
    @PreAuthorize("hasAuthority('" + Permissions.PHOTO_READ + "')")
    @GetMapping("/api/v1/photos/{photoId}/versions")
    ApiResponse<List<PhotoEditVersionDto>> listVersions(@PathVariable UUID photoId) {
        UUID userId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(editService.listVersions(userId, photoId));
    }

    @Operation(summary = "恢复到指定版本", description = "将照片恢复到指定的编辑版本")
    @PreAuthorize("hasAuthority('" + Permissions.PHOTO_WRITE + "')")
    @PostMapping("/api/v1/photos/{photoId}/versions/{versionId}/revert")
    ApiResponse<Void> revertToVersion(
            @PathVariable UUID photoId,
            @PathVariable UUID versionId
    ) {
        UUID userId = currentUserContext.requireCurrentUserId();
        editService.revertToVersion(userId, photoId, versionId);
        return ApiResponse.success();
    }

    // ─── 相册分享 ───

    @Operation(summary = "创建相册分享链接", description = "为指定相册创建分享链接")
    @PreAuthorize("hasAuthority('" + Permissions.PHOTO_WRITE + "')")
    @PostMapping("/api/v1/photos/albums/{albumId}/share")
    ApiResponse<PhotoShareLinkDto> createAlbumShare(
            @PathVariable UUID albumId,
            @Valid @RequestBody CreateAlbumShareRequest body
    ) {
        UUID userId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(albumService.createAlbumShare(userId, albumId, body));
    }

    @Operation(summary = "获取相册分享链接列表", description = "返回指定相册的所有分享链接")
    @PreAuthorize("hasAuthority('" + Permissions.PHOTO_READ + "')")
    @GetMapping("/api/v1/photos/albums/{albumId}/share")
    ApiResponse<List<PhotoShareLinkDto>> listAlbumShares(@PathVariable UUID albumId) {
        UUID userId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(albumService.listAlbumShares(userId, albumId));
    }

    @Operation(summary = "撤销相册分享", description = "撤销指定的相册分享链接")
    @PreAuthorize("hasAuthority('" + Permissions.PHOTO_WRITE + "')")
    @DeleteMapping("/api/v1/photos/share/{shareId}")
    ApiResponse<Void> revokeAlbumShare(@PathVariable UUID shareId) {
        UUID userId = currentUserContext.requireCurrentUserId();
        albumService.revokeAlbumShare(userId, shareId);
        return ApiResponse.success();
    }

    @Operation(summary = "访问分享相册", description = "通过分享令牌访问共享相册，可选密码验证")
    @PostMapping("/api/v1/public/photos/share/{token}/authorize")
    ApiResponse<ShareAccessSessionDto> authorizeSharedAlbum(
            @PathVariable String token,
            @RequestBody(required = false) ShareAuthorizationRequest body,
            HttpServletRequest request
    ) {
        return ApiResponse.success(albumService.issueSharedAlbumSession(
                token, body == null ? null : body.password(), request.getRemoteAddr()));
    }

    @Operation(summary = "访问分享相册", description = "通过短期分享会话分页访问共享相册")
    @GetMapping("/api/v1/public/photos/share/{token}")
    ApiResponse<PhotoSharedAlbumDto> accessSharedAlbum(
            @PathVariable String token,
            @RequestHeader(value = "X-OmniNest-Share-Session", required = false) String sessionToken,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "50") int size
    ) {
        return ApiResponse.success(albumService.accessSharedAlbum(token, sessionToken, page, size));
    }

    // ─── 照片分享 ───

    @Operation(summary = "创建照片分享链接", description = "为单张照片创建分享链接")
    @PreAuthorize("hasAuthority('" + Permissions.PHOTO_WRITE + "')")
    @PostMapping("/api/v1/photos/{photoId}/share")
    ApiResponse<PhotoShareLinkDto> createPhotoShare(
            @PathVariable UUID photoId,
            @Valid @RequestBody CreateAlbumShareRequest body
    ) {
        UUID userId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(albumService.createPhotoShare(userId, photoId, body));
    }

    @Operation(summary = "获取照片分享链接列表", description = "返回单张照片的所有分享链接")
    @PreAuthorize("hasAuthority('" + Permissions.PHOTO_READ + "')")
    @GetMapping("/api/v1/photos/{photoId}/share")
    ApiResponse<List<PhotoShareLinkDto>> listPhotoShares(@PathVariable UUID photoId) {
        UUID userId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(albumService.listPhotoShares(userId, photoId));
    }

    @Operation(summary = "访问分享照片", description = "通过分享令牌发起共享单张照片会话，可选密码验证")
    @PostMapping("/api/v1/public/photos/item/{token}/authorize")
    ApiResponse<ShareAccessSessionDto> authorizeSharedPhoto(
            @PathVariable String token,
            @RequestBody(required = false) ShareAuthorizationRequest body,
            HttpServletRequest request
    ) {
        return ApiResponse.success(albumService.issueSharedPhotoSession(
                token, body == null ? null : body.password(), request.getRemoteAddr()));
    }

    @Operation(summary = "访问分享照片", description = "通过短期分享会话访问共享单张照片")
    @GetMapping("/api/v1/public/photos/item/{token}")
    ApiResponse<PhotoItemDto> accessSharedPhoto(
            @PathVariable String token,
            @RequestHeader(value = "X-OmniNest-Share-Session", required = false) String sessionToken
    ) {
        return ApiResponse.success(albumService.accessSharedPhoto(token, sessionToken));
    }

    // ─── 管理 ───

    @Operation(summary = "扫描照片库", description = "触发照片库扫描，检测新增或变更的照片文件")
    @PreAuthorize("hasAuthority('" + Permissions.PHOTO_ADMIN + "')")
    @PostMapping("/api/v1/admin/photos/scan")
    ApiResponse<PhotoScanJobDto> scanLibrary() {
        UUID userId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(adminService.createScanJob(userId));
    }

    @Operation(summary = "查询扫描任务状态", description = "查询指定照片扫描任务的执行状态")
    @PreAuthorize("hasAuthority('" + Permissions.PHOTO_READ + "')")
    @GetMapping("/api/v1/admin/photos/scan/{jobId}/status")
    ApiResponse<PhotoScanJobDto> scanStatus(@PathVariable UUID jobId) {
        UUID userId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(adminService.scanJob(userId, jobId));
    }

    @Operation(summary = "获取 RAW 预览地址", description = "返回指定 RAW 照片的预览图下载地址")
    @PreAuthorize("hasAuthority('" + Permissions.PHOTO_READ + "')")
    @GetMapping("/api/v1/photos/{photoId}/raw-preview")
    ApiResponse<Map<String, String>> rawPreviewUrl(@PathVariable UUID photoId) {
        UUID userId = currentUserContext.requireCurrentUserId();
        String url = adminService.getRawPreviewUrl(userId, photoId);
        if (url == null) {
            return ApiResponse.success(Map.of());
        }
        return ApiResponse.success(Map.of("url", url));
    }

    @Operation(summary = "重建缩略图", description = "创建异步任务重生成所有缺失的照片缩略图")
    @PreAuthorize("hasAuthority('" + Permissions.PHOTO_ADMIN + "')")
    @PostMapping("/api/v1/admin/photos/thumbnails/regenerate")
    ApiResponse<Map<String, String>> regenerateThumbnails() {
        UUID userId = currentUserContext.requireCurrentUserId();
        UUID taskId = adminService.createThumbnailRegenerationTask(userId);
        return ApiResponse.success(Map.of("taskId", taskId.toString()));
    }

    // ─── 图像分析与人脸聚类 ───

    @Operation(summary = "获取人脸聚类列表", description = "返回图像分析识别的人脸聚类分组")
    @PreAuthorize("hasAuthority('" + Permissions.PHOTO_READ + "')")
    @GetMapping("/api/v1/photos/people")
    ApiResponse<List<PhotoFaceClusterDto>> faceClusters() {
        requireAiEnabled();
        UUID userId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(photoAiService.getClusters(userId));
    }

    @Operation(summary = "获取聚类照片列表", description = "返回指定人脸聚类中的所有照片")
    @PreAuthorize("hasAuthority('" + Permissions.PHOTO_READ + "')")
    @GetMapping("/api/v1/photos/people/{clusterId}")
    ApiResponse<List<PhotoItemDto>> photosByCluster(@PathVariable UUID clusterId) {
        requireAiEnabled();
        UUID userId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(photoAiService.getPhotosByCluster(userId, clusterId));
    }

    @Operation(summary = "命名人物聚类", description = "为指定的人脸聚类设置人物名称")
    @PreAuthorize("hasAuthority('" + Permissions.PHOTO_WRITE + "')")
    @PutMapping("/api/v1/photos/people/{clusterId}")
    ApiResponse<Void> nameCluster(
            @PathVariable UUID clusterId,
            @Valid @RequestBody NameClusterRequest body
    ) {
        requireAiEnabled();
        UUID userId = currentUserContext.requireCurrentUserId();
        photoAiService.nameCluster(userId, clusterId, body.name());
        return ApiResponse.success();
    }

    @Operation(summary = "重新聚类人脸", description = "异步重新聚类已有的人脸分析结果")
    @PreAuthorize("hasAuthority('" + Permissions.PHOTO_WRITE + "')")
    @PostMapping("/api/v1/photos/ai/recluster")
    ApiResponse<PhotoAiTaskDto> reclusterFaces() {
        requireAiEnabled();
        UUID userId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(photoAiTaskService.queueFaceRecluster(userId));
    }

    @Operation(summary = "重分析照片库", description = "异步分页重建当前用户全部照片的图像分析和人脸聚类结果")
    @PreAuthorize("hasAuthority('" + Permissions.PHOTO_WRITE + "')")
    @PostMapping("/api/v1/photos/ai/reanalyze")
    ApiResponse<PhotoAiTaskDto> reanalyzeLibrary() {
        requireAiEnabled();
        UUID userId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(photoAiTaskService.queueLibraryReanalysis(userId));
    }

    // ─── 备份状态 ───

    @Operation(summary = "查询备份状态", description = "查询指定设备的照片备份状态")
    @PreAuthorize("hasAuthority('" + Permissions.PHOTO_WRITE + "')")
    @PostMapping("/api/v1/photos/backup/status")
    ApiResponse<PhotoBackupStatusDto> backupStatus(@Valid @RequestBody BackupStatusRequest body) {
        if (!photosRuntimeConfigService.isBackupEnabled()) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "照片备份功能未启用");
        }
        UUID userId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(backupService.getBackupStatus(userId, body.deviceId()));
    }

    @Operation(summary = "上报备份进度", description = "客户端上报照片备份进度信息")
    @PreAuthorize("hasAuthority('" + Permissions.PHOTO_WRITE + "')")
    @PostMapping("/api/v1/photos/backup/report")
    ApiResponse<Void> reportBackup(@Valid @RequestBody BackupReportRequest body) {
        if (!photosRuntimeConfigService.isBackupEnabled()) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "照片备份功能未启用");
        }
        UUID userId = currentUserContext.requireCurrentUserId();
        backupService.reportBackup(userId, body.deviceId(), body.photoCount());
        return ApiResponse.success();
    }

    @Operation(summary = "检查重复照片", description = "通过内容哈希检查照片是否已备份")
    @PreAuthorize("hasAuthority('" + Permissions.PHOTO_WRITE + "')")
    @PostMapping("/api/v1/photos/backup/check-duplicate")
    ApiResponse<List<String>> checkDuplicate(@Valid @RequestBody CheckDuplicateRequest body) {
        if (!photosRuntimeConfigService.isBackupEnabled()) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "照片备份功能未启用");
        }
        if (body.contentHashes() == null || body.contentHashes().isEmpty()) {
            return ApiResponse.success(List.of());
        }
        if (body.contentHashes().size() > 1000) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "单次查询不能超过 1000 个哈希值");
        }
        UUID userId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(backupService.checkDuplicate(userId, body.contentHashes()));
    }

    /**
     * 运行时检查图像分析功能是否启用（基于配置中心 photo.ai.enabled）。
     * 未启用时抛出业务异常。
     */
    private void requireAiEnabled() {
        if (!photosRuntimeConfigService.isAiEnabled()) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "图像分析功能未启用，请在配置中心开启 photo.ai.enabled");
        }
    }

    private void markLegacyListEndpoint(HttpServletResponse response, String successorPath) {
        response.setHeader("Deprecation", "true");
        response.setHeader("Sunset", "Sat, 31 Oct 2026 00:00:00 GMT");
        response.setHeader("Link", "<" + successorPath + ">; rel=\"successor-version\"");
    }

    private PhotoItemDto toLegacyPhotoItem(PhotoListItemDto item) {
        return new PhotoItemDto(
                item.id(),
                item.fileNodeId(),
                item.title(),
                item.description(),
                item.width(),
                item.height(),
                item.orientation(),
                item.dateTaken(),
                null,
                null,
                null,
                null,
                null,
                null,
                null,
                null,
                null,
                null,
                item.gpsLatitude(),
                item.gpsLongitude(),
                item.gpsLocation(),
                item.format(),
                item.fileSize(),
                item.coverUrl(),
                null,
                item.metadataStatus(),
                item.favorite(),
                item.createdAt(),
                item.tags(),
                Map.of(),
                null
        );
    }

    @Operation(summary = "获取照片关系图谱", description = "返回相册、时间、地点、人物之间的共现关系边")
    @PreAuthorize("hasAuthority('" + Permissions.PHOTO_READ + "')")
    @GetMapping("/api/v1/photos/relations")
    ApiResponse<PhotoRelationsDto> relations() {
        UUID userId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(relationService.relations(userId));
    }
}

