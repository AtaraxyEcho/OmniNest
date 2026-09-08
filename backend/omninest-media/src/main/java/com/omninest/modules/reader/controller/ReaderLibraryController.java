package com.omninest.modules.reader.controller;

import com.omninest.common.api.ApiResponse;
import com.omninest.common.security.CurrentUserContext;
import com.omninest.common.security.Permissions;
import com.omninest.modules.reader.domain.ReaderItem;
import com.omninest.modules.file.dto.FilePurgeTaskDto;
import com.omninest.modules.reader.dto.ReaderDtos;
import com.omninest.modules.reader.dto.ReaderDtos.CreateAnnotationRequest;
import com.omninest.modules.reader.dto.ReaderDtos.CreateBookmarkRequest;
import com.omninest.modules.reader.dto.ReaderDtos.CreateNoteRequest;
import com.omninest.modules.reader.dto.ReaderDtos.ReaderAnnotationDto;
import com.omninest.modules.reader.dto.ReaderDtos.ReaderBookmarkDto;
import com.omninest.modules.reader.dto.ReaderDtos.ReaderDashboardDto;
import com.omninest.modules.reader.dto.ReaderDtos.ReaderItemDetailDto;
import com.omninest.modules.reader.dto.ReaderDtos.ReaderItemDto;
import com.omninest.modules.reader.dto.ReaderDtos.ReaderNoteDto;
import com.omninest.modules.reader.dto.ReaderDtos.ReaderReadingStatsDto;
import com.omninest.modules.reader.dto.ReaderDtos.ReaderStatsOverviewDto;
import com.omninest.modules.reader.dto.ReaderDtos.RecordSessionRequest;
import com.omninest.modules.reader.dto.ReaderDtos.UpdateAnnotationRequest;
import com.omninest.modules.reader.dto.ReaderDtos.UpdateItemMetadataRequest;
import com.omninest.modules.reader.dto.ReaderDtos.UpdateNoteRequest;
import com.omninest.modules.reader.dto.ReaderDtos.UpdateProgressRequest;
import com.omninest.modules.reader.dto.ReaderFileTicketDto;
import com.omninest.modules.reader.service.ComicPageAssetService.PageDownloadDescriptor;
import com.omninest.modules.reader.service.ReaderComicManifestDtos.ComicManifestDto;
import com.omninest.modules.reader.service.ReaderAnnotationService;
import com.omninest.modules.reader.service.ReaderBookshelfService;
import com.omninest.modules.reader.service.ReaderBookmarkService;
import com.omninest.modules.reader.service.ReaderDashboardService;
import com.omninest.modules.reader.service.ReaderComicManifestService;
import com.omninest.modules.reader.service.ReaderImportService;
import com.omninest.modules.reader.service.ReaderItemService;
import com.omninest.modules.reader.service.ReaderNoteService;
import com.omninest.modules.reader.service.ReaderProgressService;
import com.omninest.modules.reader.service.ReaderStatsService;
import com.omninest.modules.reader.service.ReaderTextManifestService;
import com.omninest.modules.reader.service.ReaderTextParseSubmissionService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ContentDisposition;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.web.servlet.mvc.method.annotation.StreamingResponseBody;

/**
 * 阅读器控制器：提供阅读条目、进度、书签、批注、笔记、书架、统计等 REST API。
 */
@Tag(name = "阅读器", description = "阅读资源的管理与阅读操作")
@RestController
@RequiredArgsConstructor
public class ReaderLibraryController {

    private final CurrentUserContext currentUserContext;
    private final ReaderDashboardService readerDashboardService;
    private final ReaderItemService readerItemService;
    private final ReaderProgressService readerProgressService;
    private final ReaderBookmarkService readerBookmarkService;
    private final ReaderAnnotationService readerAnnotationService;
    private final ReaderNoteService readerNoteService;
    private final ReaderBookshelfService readerBookshelfService;
    private final ReaderStatsService readerStatsService;
    private final ReaderImportService readerImportService;
    private final ReaderComicManifestService comicManifestService;
    private final ReaderTextManifestService textManifestService;
    private final ReaderTextParseSubmissionService textParseSubmissionService;

    // ==================== Dashboard ====================

    /**
     * 获取阅读仪表盘数据。
     */
    @Operation(summary = "获取阅读仪表盘", description = "返回用户的阅读概览信息，包括继续阅读、最近条目等")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/reader/dashboard")
    ApiResponse<ReaderDashboardDto> dashboard() {
        return ApiResponse.success(readerDashboardService.getDashboard(currentUserContext.requireCurrentUserId()));
    }

    // ==================== Items ====================

    /**
     * 列出阅读条目，支持按类型和关键词过滤。
     */
    @Operation(summary = "获取阅读条目列表", description = "返回当前用户的阅读条目列表，可按类型和关键词过滤")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/reader/items")
    ApiResponse<List<ReaderItemDto>> listItems(
            @RequestParam(required = false) String itemType,
            @RequestParam(required = false) String contentKind,
            @RequestParam(required = false) String query
    ) {
        return ApiResponse.success(readerItemService.listItems(currentUserContext.requireCurrentUserId(), itemType, contentKind, query));
    }

    /**
     * 获取阅读条目详情（含当前阅读进度）。
     */
    @Operation(summary = "获取阅读条目详情", description = "返回指定阅读条目的详细信息，包含当前阅读进度")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/reader/items/{itemId}")
    ApiResponse<ReaderItemDetailDto> getItemDetail(@PathVariable UUID itemId) {
        return ApiResponse.success(readerItemService.getItemDetail(currentUserContext.requireCurrentUserId(), itemId));
    }

    /**
     * 删除阅读条目及所有关联数据。
     */
    @Operation(summary = "删除阅读条目", description = "删除指定的阅读条目及其关联的进度、书签、批注、笔记等数据")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    @DeleteMapping("/api/v1/reader/items/{itemId}")
    ApiResponse<FilePurgeTaskDto> deleteItem(
            @PathVariable UUID itemId,
            @RequestParam(defaultValue = "false") boolean cascade
    ) {
        UUID taskId = readerItemService.deleteItem(
                currentUserContext.requireCurrentUserId(),
                itemId,
                cascade
        );
        return ApiResponse.success(FilePurgeTaskDto.queued(taskId));
    }

    /**
     * 下载阅读条目的源文件。
     */
    @Operation(summary = "下载阅读文件", description = "下载指定阅读条目的源文件（EPUB/TXT）")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping(value = "/api/v1/reader/items/{itemId}/file", produces = MediaType.APPLICATION_OCTET_STREAM_VALUE)
    ResponseEntity<StreamingResponseBody> downloadFile(@PathVariable UUID itemId) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        ReaderItemService.DownloadDescriptor descriptor = readerItemService.prepareDownload(ownerUserId, itemId);
        // 使用 Spring 内置 ContentDisposition 处理 RFC 6266 编码
        ContentDisposition disposition = ContentDisposition
                .attachment()
                .filename(descriptor.fileName(), StandardCharsets.UTF_8)
                .build();
        StreamingResponseBody body = outputStream -> readerItemService.streamFile(descriptor, outputStream);
        return ResponseEntity.ok()
                .header(HttpHeaders.CONTENT_DISPOSITION, disposition.toString())
                .contentLength(descriptor.sizeBytes())
                .body(body);
    }

    /**
     * 获取阅读源文件临时下载票据。
     *
     * @param itemId 阅读条目标识
     * @return 临时下载票据
     */
    @Operation(summary = "获取阅读文件下载票据", description = "返回经过当前用户授权的临时签名下载地址")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/reader/items/{itemId}/file-ticket")
    ApiResponse<ReaderFileTicketDto> createFileTicket(@PathVariable UUID itemId) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(readerItemService.createFileTicket(ownerUserId, itemId));
    }

    // ==================== Progress ====================

    /**
     * 更新阅读进度。
     */
    @Operation(summary = "更新阅读进度", description = "更新指定阅读条目的阅读进度（Upsert 语义）")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    @PutMapping("/api/v1/reader/items/{itemId}/progress")
    ApiResponse<Void> updateProgress(@PathVariable UUID itemId, @Valid @RequestBody UpdateProgressRequest request) {
        readerProgressService.updateProgress(currentUserContext.requireCurrentUserId(), itemId, request);
        return ApiResponse.success();
    }

    // ==================== Bookmarks ====================

    /**
     * 列出指定条目的所有书签。
     */
    @Operation(summary = "获取书签列表", description = "返回指定阅读条目的所有书签")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/reader/items/{itemId}/bookmarks")
    ApiResponse<List<ReaderBookmarkDto>> listBookmarks(@PathVariable UUID itemId) {
        return ApiResponse.success(readerBookmarkService.listBookmarks(currentUserContext.requireCurrentUserId(), itemId));
    }

    /**
     * 创建书签。
     */
    @Operation(summary = "创建书签", description = "在指定阅读条目中创建书签")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    @PostMapping("/api/v1/reader/items/{itemId}/bookmarks")
    ApiResponse<ReaderBookmarkDto> createBookmark(@PathVariable UUID itemId, @Valid @RequestBody CreateBookmarkRequest request) {
        return ApiResponse.success(readerBookmarkService.createBookmark(currentUserContext.requireCurrentUserId(), itemId, request));
    }

    /**
     * 删除书签。
     */
    @Operation(summary = "删除书签", description = "删除指定的书签")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    @DeleteMapping("/api/v1/reader/bookmarks/{bookmarkId}")
    ApiResponse<Void> deleteBookmark(@PathVariable UUID bookmarkId) {
        readerBookmarkService.deleteBookmark(currentUserContext.requireCurrentUserId(), bookmarkId);
        return ApiResponse.success();
    }

    // ==================== Annotations ====================

    /**
     * 列出指定条目的所有批注。
     */
    @Operation(summary = "获取批注列表", description = "返回指定阅读条目的所有批注（高亮 + 附注）")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/reader/items/{itemId}/annotations")
    ApiResponse<List<ReaderAnnotationDto>> listAnnotations(@PathVariable UUID itemId) {
        return ApiResponse.success(readerAnnotationService.listAnnotations(currentUserContext.requireCurrentUserId(), itemId));
    }

    /**
     * 创建批注。
     */
    @Operation(summary = "创建批注", description = "在指定阅读条目中创建高亮批注")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    @PostMapping("/api/v1/reader/items/{itemId}/annotations")
    ApiResponse<ReaderAnnotationDto> createAnnotation(
            @PathVariable UUID itemId,
            @Valid @RequestBody CreateAnnotationRequest request
    ) {
        return ApiResponse.success(readerAnnotationService.createAnnotation(currentUserContext.requireCurrentUserId(), itemId, request));
    }

    /**
     * 更新批注（仅允许更新备注和颜色）。
     */
    @Operation(summary = "更新批注", description = "更新指定批注的备注和颜色")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    @PutMapping("/api/v1/reader/annotations/{annotationId}")
    ApiResponse<ReaderAnnotationDto> updateAnnotation(@PathVariable UUID annotationId, @Valid @RequestBody UpdateAnnotationRequest request) {
        return ApiResponse.success(readerAnnotationService.updateAnnotation(currentUserContext.requireCurrentUserId(), annotationId, request));
    }

    /**
     * 删除批注。
     */
    @Operation(summary = "删除批注", description = "删除指定的批注")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    @DeleteMapping("/api/v1/reader/annotations/{annotationId}")
    ApiResponse<Void> deleteAnnotation(@PathVariable UUID annotationId) {
        readerAnnotationService.deleteAnnotation(currentUserContext.requireCurrentUserId(), annotationId);
        return ApiResponse.success();
    }

    // ==================== Notes ====================

    /**
     * 列出指定条目的所有笔记。
     */
    @Operation(summary = "获取笔记列表", description = "返回指定阅读条目的所有笔记")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/reader/items/{itemId}/notes")
    ApiResponse<List<ReaderNoteDto>> listNotes(@PathVariable UUID itemId) {
        return ApiResponse.success(readerNoteService.listNotes(currentUserContext.requireCurrentUserId(), itemId));
    }

    /**
     * 创建笔记。
     */
    @Operation(summary = "创建笔记", description = "在指定阅读条目中创建笔记")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    @PostMapping("/api/v1/reader/items/{itemId}/notes")
    ApiResponse<ReaderNoteDto> createNote(@PathVariable UUID itemId, @Valid @RequestBody CreateNoteRequest request) {
        return ApiResponse.success(readerNoteService.createNote(currentUserContext.requireCurrentUserId(), itemId, request));
    }

    /**
     * 更新笔记。
     */
    @Operation(summary = "更新笔记", description = "更新指定笔记的内容")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    @PutMapping("/api/v1/reader/notes/{noteId}")
    ApiResponse<ReaderNoteDto> updateNote(@PathVariable UUID noteId, @Valid @RequestBody UpdateNoteRequest request) {
        return ApiResponse.success(readerNoteService.updateNote(currentUserContext.requireCurrentUserId(), noteId, request));
    }

    /**
     * 删除笔记。
     */
    @Operation(summary = "删除笔记", description = "删除指定的笔记")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    @DeleteMapping("/api/v1/reader/notes/{noteId}")
    ApiResponse<Void> deleteNote(@PathVariable UUID noteId) {
        readerNoteService.deleteNote(currentUserContext.requireCurrentUserId(), noteId);
        return ApiResponse.success();
    }

    // ==================== Bookshelf ====================

    /**
     * 切换书架状态：已存在则移除，不存在则添加。
     */
    @Operation(summary = "切换书架状态", description = "将指定阅读条目添加到书架或从书架移除")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    @PostMapping("/api/v1/reader/items/{itemId}/bookshelf")
    ApiResponse<Boolean> toggleBookshelf(@PathVariable UUID itemId) {
        return ApiResponse.success(readerBookshelfService.toggleBookshelf(currentUserContext.requireCurrentUserId(), itemId));
    }

    // ==================== Sessions ====================

    /**
     * 记录一次阅读会话。
     */
    @Operation(summary = "记录阅读会话", description = "记录用户的一次阅读会话（时长、起止时间）")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    @PostMapping("/api/v1/reader/items/{itemId}/sessions")
    ApiResponse<Void> recordSession(
            @PathVariable UUID itemId,
            @Valid @RequestBody RecordSessionRequest request
    ) {
        readerStatsService.recordSession(currentUserContext.requireCurrentUserId(), itemId, request);
        return ApiResponse.success();
    }

    // ==================== Stats ====================

    /**
     * 获取用户的阅读统计数据。
     */
    @Operation(summary = "获取阅读统计", description = "返回用户的阅读统计数据，包括今日时长、本周时长、连续天数等")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/reader/stats")
    ApiResponse<ReaderReadingStatsDto> getStats() {
        return ApiResponse.success(readerStatsService.getStats(currentUserContext.requireCurrentUserId()));
    }

    /**
     * 获取阅读统计概览（统计页）：每日分钟数、完成/在读计数与在读列表。
     */
    @Operation(summary = "获取阅读统计概览", description = "返回最近 N 天每日阅读时长、完成/在读计数与在读条目列表")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/reader/stats/overview")
    ApiResponse<ReaderStatsOverviewDto> getStatsOverview(
            @RequestParam(name = "days", defaultValue = "14") int days) {
        return ApiResponse.success(
                readerStatsService.getStatsOverview(currentUserContext.requireCurrentUserId(), days));
    }

    // ==================== Admin ====================

    /**
     * 更新自己的条目元数据（用户级，首次打开时前端回传 EPUB 元数据）。
     */
    @Operation(summary = "更新条目元数据", description = "更新指定阅读条目的标题、作者等元数据（仅限自己的条目）")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    @PutMapping("/api/v1/reader/items/{itemId}/metadata")
    ApiResponse<Void> updateMyItemMetadata(@PathVariable UUID itemId, @Valid @RequestBody UpdateItemMetadataRequest request) {
        readerItemService.updateMetadata(currentUserContext.requireCurrentUserId(), itemId, request);
        return ApiResponse.success();
    }

    /**
     * 管理员更新任意条目元数据。
     */
    @Operation(summary = "管理员更新元数据", description = "管理员更新指定阅读条目的元数据（任意条目）")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_LIBRARY_MANAGE + "')")
    @PutMapping("/api/v1/admin/reader/items/{itemId}/metadata")
    ApiResponse<Void> updateItemMetadata(@PathVariable UUID itemId, @Valid @RequestBody UpdateItemMetadataRequest request) {
        readerItemService.updateMetadataAsAdmin(itemId, request);
        return ApiResponse.success();
    }

    /**
     * 下载封面图片。
     */
    @Operation(summary = "下载封面图片", description = "下载指定阅读条目的封面图片")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping(value = "/api/v1/reader/items/{itemId}/cover")
    ResponseEntity<StreamingResponseBody> downloadCover(@PathVariable UUID itemId) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        ReaderItemService.DownloadDescriptor descriptor = readerItemService.prepareCoverDownload(
                ownerUserId,
                itemId
        );
        MediaType contentType = MediaType.parseMediaType(descriptor.contentType());
        StreamingResponseBody body = outputStream -> readerItemService.streamFile(descriptor, outputStream);
        return ResponseEntity.ok()
                .contentType(contentType)
                .contentLength(descriptor.sizeBytes())
                .body(body);
    }

    /**
     * 上传封面图片。
     */
    @Operation(summary = "上传封面图片", description = "为指定阅读条目上传封面图片")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    @PostMapping("/api/v1/reader/items/{itemId}/cover")
    ApiResponse<Void> uploadCover(@PathVariable UUID itemId, @RequestParam("file") MultipartFile file) {
        readerItemService.uploadCover(currentUserContext.requireCurrentUserId(), itemId, file);
        return ApiResponse.success();
    }

    /**
     * 从文件节点设置封面。
     */
    @Operation(summary = "从文件节点设置封面", description = "将已上传的文件节点设为阅读条目的封面")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    @PostMapping("/api/v1/reader/items/{itemId}/cover/file")
    ApiResponse<Void> setCoverFromFile(@PathVariable UUID itemId, @Valid @RequestBody ReaderDtos.SetCoverFromFileRequest request) {
        readerItemService.setCoverFromFile(currentUserContext.requireCurrentUserId(), itemId, request.fileNodeId());
        return ApiResponse.success();
    }

    /**
     * 重新解析阅读条目。
     */
    @Operation(summary = "重新解析阅读条目", description = "文本条目用于前端清理派生缓存，漫画条目会重建来源清单和页面索引")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    @PostMapping("/api/v1/reader/items/{itemId}/reparse")
    ApiResponse<ReaderItemDto> reparseItem(@PathVariable UUID itemId) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        ReaderItem item = readerItemService.requireOwnedItem(ownerUserId, itemId);
        if ("COMIC".equalsIgnoreCase(item.getContentKind())) {
            comicManifestService.enqueueManifestReparse(itemId);
            item = readerItemService.requireOwnedItem(ownerUserId, itemId);
        } else {
            textParseSubmissionService.submit(item, true);
            item = readerItemService.requireOwnedItem(ownerUserId, itemId);
        }
        boolean onBookshelf = readerBookshelfService.isOnBookshelf(ownerUserId, itemId);
        return ApiResponse.success(readerItemService.toDto(item, onBookshelf));
    }

    // ── 漫画清单 ────────────────────────────────────────────────

    /**
     * 请求异步生成漫画清单。
     */
    @Operation(summary = "请求异步生成漫画清单", description = "创建或唤醒漫画来源解析任务，页面清单由 Worker 异步生成")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    @PostMapping("/api/v1/reader/items/{itemId}/comic/manifest")
    ApiResponse<ComicManifestDto> generateComicManifest(@PathVariable UUID itemId) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        ReaderItem item = readerItemService.requireOwnedItem(ownerUserId, itemId);
        comicManifestService.enqueueManifestParse(item);
        return ApiResponse.success(comicManifestService.getManifest(ownerUserId, itemId));
    }

    /**
     * 获取漫画清单。
     */
    @Operation(summary = "获取漫画清单", description = "返回漫画条目的来源文件、目录树和页面列表")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/reader/items/{itemId}/comic/manifest")
    ApiResponse<ComicManifestDto> getComicManifest(@PathVariable UUID itemId) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        readerItemService.requireItem(ownerUserId, itemId);
        return ApiResponse.success(comicManifestService.getManifest(ownerUserId, itemId));
    }

    // ── 漫画来源管理 ──────────────────────────────────────────────

    /**
     * 重试失败的漫画来源解析。
     */
    @Operation(summary = "重试漫画来源解析", description = "重新解析失败的漫画来源文件")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    @PostMapping("/api/v1/reader/items/{itemId}/comic/sources/{sourceId}/retry")
    ApiResponse<Void> retryComicSource(
            @PathVariable UUID itemId,
            @PathVariable UUID sourceId) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        readerItemService.requireOwnedItem(ownerUserId, itemId);
        comicManifestService.publishRetryTask(itemId, sourceId);
        return ApiResponse.success(null);
    }

    /**
     * 删除漫画来源及其页面。
     */
    @Operation(summary = "删除漫画来源", description = "删除指定漫画来源及其页面")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    @DeleteMapping("/api/v1/reader/items/{itemId}/comic/sources/{sourceId}")
    ApiResponse<Void> deleteComicSource(
            @PathVariable UUID itemId,
            @PathVariable UUID sourceId) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        readerItemService.requireOwnedItem(ownerUserId, itemId);
        comicManifestService.deleteSource(itemId, sourceId);
        return ApiResponse.success(null);
    }

    // ── 漫画页面图片 ──────────────────────────────────────────────

    /**
     * 获取漫画页面图片。
     *
     * 优先流式返回页面派生对象，兼容从 CBZ/ZIP 来源流式提取旧数据页面。
     */
    @Operation(summary = "获取漫画页面图片", description = "从 CBZ/ZIP 存档中提取指定页面的图片")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping(value = "/api/v1/reader/pages/{pageId}/image", produces = MediaType.APPLICATION_OCTET_STREAM_VALUE)
    ResponseEntity<StreamingResponseBody> getPageImage(@PathVariable UUID pageId) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        PageDownloadDescriptor descriptor = comicManifestService.preparePageImageDownload(
                ownerUserId,
                pageId
        );
        MediaType contentType = MediaType.parseMediaType(descriptor.mimeType());
        StreamingResponseBody body = outputStream -> comicManifestService.streamPageImage(
                descriptor,
                outputStream
        );
        ResponseEntity.BodyBuilder response = ResponseEntity.ok().contentType(contentType);
        if (descriptor.sizeBytes() > 0) {
            response.contentLength(descriptor.sizeBytes());
        }
        return response.body(body);
    }

    /**
     * 获取服务端持久化的文本书籍章节清单。
     *
     * @param itemId 阅读条目 ID
     * @return 文本章节清单
     */
    @Operation(summary = "获取文本书籍清单", description = "返回 EPUB/TXT 的服务端解析元数据和稳定章节顺序")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/reader/items/{itemId}/text/manifest")
    ApiResponse<ReaderTextManifestService.TextManifestDto> getTextManifest(@PathVariable UUID itemId) {
        return ApiResponse.success(textManifestService.getManifest(
                currentUserContext.requireCurrentUserId(),
                itemId
        ));
    }

    // ── 导入 ──────────────────────────────────────────────────────

    @Operation(summary = "导入文件到阅读器", description = "从文件管理导入 EPUB/TXT/CBZ/ZIP 文件，支持内容级去重")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    @PostMapping("/api/v1/reader/import")
    ApiResponse<ReaderItemDto> importFile(@Valid @RequestBody ReaderDtos.ImportFileRequest request) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        ReaderItem item = readerImportService.importFile(
                ownerUserId,
                request.fileNodeId(),
                request.force(),
                request.contentKindOverride());
        boolean onBookshelf = true; // 导入时自动加入书架
        return ApiResponse.success(readerItemService.toDto(item, onBookshelf));
    }

    @Operation(summary = "取消阅读导入", description = "取消排队中或执行中的解析任务，保留源文件和可重试条目")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_WRITE + "')")
    @PostMapping("/api/v1/reader/items/{itemId}/import/cancel")
    ApiResponse<Void> cancelImport(@PathVariable UUID itemId) {
        readerImportService.cancelImport(currentUserContext.requireCurrentUserId(), itemId);
        return ApiResponse.success(null);
    }

    @Operation(summary = "列出可导入的文件", description = "列出个人空间和共享空间中可导入的 EPUB/TXT/CBZ/ZIP 文件")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_READ + "')")
    @GetMapping("/api/v1/reader/import/candidates")
    ApiResponse<List<ReaderDtos.ImportCandidateDto>> importCandidates() {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(readerImportService.importCandidates(ownerUserId));
    }
}
