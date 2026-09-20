package com.omninest.modules.file.controller;

import com.omninest.common.api.ApiResponse;
import com.omninest.common.api.PageResponse;
import com.omninest.common.security.CurrentUserContext;
import com.omninest.common.security.Permissions;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.dto.AcceptShareRequest;
import com.omninest.modules.file.dto.ShareAccessSessionDto;
import com.omninest.modules.file.dto.ShareAuthorizationRequest;
import com.omninest.modules.file.dto.BatchDownloadRequest;
import com.omninest.modules.file.dto.BatchDownloadUrlRequest;
import com.omninest.modules.file.dto.BatchFileOperationRequest;
import com.omninest.modules.file.dto.BatchMoveFileNodeRequest;
import com.omninest.modules.file.dto.CompleteFileUploadPartRequest;
import com.omninest.modules.file.dto.CompleteFileUploadRequest;
import com.omninest.modules.file.dto.CopyFileRequest;
import com.omninest.modules.file.dto.CreateExternalStorageRequest;
import com.omninest.modules.file.dto.CreateFileUploadSessionRequest;
import com.omninest.modules.file.dto.CreateFolderRequest;
import com.omninest.modules.file.dto.CreateOfflineDownloadRequest;
import com.omninest.modules.file.dto.CreateShareLinkRequest;
import com.omninest.modules.file.dto.ExternalStorageAccountDto;
import com.omninest.modules.file.dto.FileDownloadUrlDto;
import com.omninest.modules.file.dto.FileNodeDto;
import com.omninest.modules.file.dto.FilePermissionDto;
import com.omninest.modules.file.dto.FilePurgeImpactDto;
import com.omninest.modules.file.dto.FilePurgeTaskDto;
import com.omninest.modules.file.dto.FileShareAccessDto;
import com.omninest.modules.file.dto.FileShareLinkDto;
import com.omninest.modules.file.dto.FileSharePreviewDto;
import com.omninest.modules.file.dto.FileVersionDto;
import com.omninest.modules.file.dto.FileSharedItemDto;
import com.omninest.modules.file.dto.FileStorageStatsDto;
import com.omninest.modules.file.dto.FileUploadPartDto;
import com.omninest.modules.file.dto.FileUploadCompleteResultDto;
import com.omninest.modules.file.dto.FileUploadPartsDto;
import com.omninest.modules.file.dto.FileUploadPolicyDto;
import com.omninest.modules.file.dto.FileUploadQueueItemDto;
import com.omninest.modules.file.dto.FileUploadSessionDto;
import com.omninest.modules.file.dto.MoveFileNodeRequest;
import com.omninest.modules.file.dto.SaveFileVersionRequest;
import com.omninest.modules.file.dto.OfflineDownloadTaskDto;
import com.omninest.modules.file.dto.PermissionRequest;
import com.omninest.modules.file.dto.RenameFileNodeRequest;
import com.omninest.modules.file.dto.SharedFileDto;
import com.omninest.modules.file.dto.UpdateExternalStorageRequest;
import com.omninest.modules.file.service.FileManagerService;
import com.omninest.modules.file.service.FileDeletionService;
import com.omninest.modules.file.service.FileQueryService;
import com.omninest.modules.file.service.FileStorageMetricsService;
import com.omninest.modules.file.service.FileUploadSessionService;
import com.omninest.modules.file.service.OfflineDownloadRequestService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.validation.Valid;
import jakarta.servlet.http.HttpServletRequest;
import java.io.IOException;
import java.util.List;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * 文件、上传、分享和离线下载接口。
 *
 * @author OmniNest
 */
@RestController
@RequiredArgsConstructor
@Tag(name = "文件管理", description = "文件上传、下载、分享、回收站等操作")
public class FileController {
    private final FileQueryService fileQueryService;
    private final FileDeletionService fileDeletionService;
    private final FileUploadSessionService fileUploadSessionService;
    private final FileManagerService fileManagerService;
    private final FileStorageMetricsService fileStorageMetricsService;
    private final OfflineDownloadRequestService offlineDownloadRequestService;
    private final CurrentUserContext currentUserContext;

    @Operation(summary = "列出文件", description = "按父目录或分类分页列出当前用户的文件节点")
    @GetMapping("/api/v1/files")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_READ + "')")
    ApiResponse<PageResponse<FileNodeDto>> listFiles(
            @RequestParam(required = false) UUID parentId,
            @RequestParam(required = false) String category,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "100") int size
    ) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        var files = fileQueryService.listFilesPage(ownerUserId, parentId, category, page, size);
        return ApiResponse.success(PageResponse.of(
                files.getContent(),
                files.getNumber(),
                files.getSize(),
                files.getTotalElements()));
    }

    @Operation(summary = "创建文件夹", description = "在指定父目录下创建新文件夹")
    @PostMapping("/api/v1/files/folders")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_WRITE + "')")
    ApiResponse<FileNodeDto> createFolder(
            @Valid @RequestBody CreateFolderRequest body
    ) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(fileQueryService.createFolder(ownerUserId, body));
    }

    @Operation(summary = "列出回收站", description = "列出当前用户回收站中已删除的文件")
    @GetMapping("/api/v1/files/recycle-bin")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_READ + "')")
    ApiResponse<PageResponse<FileNodeDto>> listRecycleBin(
            @RequestParam(defaultValue = "PERSONAL") String spaceType,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "200") int size
    ) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        SpaceType type = SpaceType.fromValue(spaceType);
        var files = fileQueryService.listRecycleBinPage(ownerUserId, type, page, size);
        return ApiResponse.success(PageResponse.of(
                files.getContent(),
                files.getNumber(),
                files.getSize(),
                files.getTotalElements()));
    }

    @Operation(summary = "列出最近文件", description = "列出当前用户最近访问的文件")
    @GetMapping("/api/v1/files/recent")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_READ + "')")
    ApiResponse<PageResponse<FileNodeDto>> listRecentFiles(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "200") int size
    ) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        var files = fileManagerService.listRecentFiles(ownerUserId);
        return ApiResponse.success(PageResponse.of(files, page, size, files.size()));
    }

    @Operation(summary = "列出收藏文件", description = "列出当前用户收藏的文件")
    @GetMapping("/api/v1/files/favorites")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_READ + "')")
    ApiResponse<PageResponse<FileNodeDto>> listFavoriteFiles(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "200") int size
    ) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        var files = fileManagerService.listFavoriteFilesPage(ownerUserId, page, size);
        return ApiResponse.success(PageResponse.of(
                files.getContent(),
                files.getNumber(),
                files.getSize(),
                files.getTotalElements()));
    }

    @Operation(summary = "重命名文件", description = "重命名指定的文件或文件夹")
    @PatchMapping("/api/v1/files/{fileId}/rename")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_WRITE + "')")
    ApiResponse<FileNodeDto> renameFile(
            @PathVariable UUID fileId,
            @Valid @RequestBody RenameFileNodeRequest body
    ) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(fileQueryService.renameNode(ownerUserId, fileId, body));
    }

    @Operation(summary = "移动文件", description = "将文件移动到指定的目标目录")
    @PatchMapping("/api/v1/files/{fileId}/move")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_WRITE + "')")
    ApiResponse<FileNodeDto> moveFile(
            @PathVariable UUID fileId,
            @Valid @RequestBody MoveFileNodeRequest body
    ) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(fileQueryService.moveNode(ownerUserId, fileId, body));
    }

    @Operation(summary = "复制文件", description = "将文件复制到指定的目标目录")
    @PostMapping("/api/v1/files/{fileId}/copy")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_WRITE + "')")
    ApiResponse<FileNodeDto> copyFile(
            @PathVariable UUID fileId,
            @RequestBody(required = false) CopyFileRequest body
    ) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(fileManagerService.copyNode(
                ownerUserId,
                fileId,
                body != null ? body.targetParentId() : null
        ));
    }


    @Operation(summary = "查询文件版本历史", description = "返回历史版本与当前内容条目")
    @GetMapping("/api/v1/files/{fileId}/versions")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_READ + "')")
    ApiResponse<List<FileVersionDto>> listFileVersions(@PathVariable UUID fileId) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(fileManagerService.listVersions(ownerUserId, fileId));
    }

    @Operation(
            summary = "保存新版本",
            description = "把当前内容存为历史版本，并将已上传对象设为当前内容"
    )
    @PostMapping("/api/v1/files/{fileId}/versions")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_WRITE + "')")
    ApiResponse<FileNodeDto> saveFileVersion(
            @PathVariable UUID fileId,
            @Valid @RequestBody SaveFileVersionRequest body
    ) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(fileManagerService.saveNewVersion(
                ownerUserId,
                fileId,
                body.objectId(),
                body.sizeBytes(),
                body.remark()
        ));
    }

    @Operation(summary = "恢复文件版本", description = "将历史版本对象设为当前内容，恢复前内容存为 RESTORE 版本")
    @PostMapping("/api/v1/files/{fileId}/versions/{versionId}/restore")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_WRITE + "')")
    ApiResponse<FileNodeDto> restoreFileVersion(
            @PathVariable UUID fileId,
            @PathVariable UUID versionId
    ) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(fileManagerService.restoreVersion(ownerUserId, fileId, versionId));
    }

    @Operation(summary = "删除文件", description = "将文件移入回收站（软删除）")
    @DeleteMapping("/api/v1/files/{fileId}")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_WRITE + "')")
    ApiResponse<Void> deleteFile(@PathVariable UUID fileId) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        fileQueryService.deleteNode(ownerUserId, fileId);
        return ApiResponse.success();
    }

    @Operation(summary = "彻底删除文件", description = "从回收站中彻底删除文件（物理删除）")
    @DeleteMapping("/api/v1/files/{fileId}/purge")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_WRITE + "')")
    ApiResponse<FilePurgeTaskDto> purgeFile(
            @PathVariable UUID fileId,
            @RequestParam(defaultValue = "false") boolean cascade,
            @RequestParam(required = false) Long expectedVersion
    ) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(FilePurgeTaskDto.queued(
                fileDeletionService.deletePermanently(
                        ownerUserId,
                        fileId,
                        cascade,
                        null,
                        expectedVersion
                )
        ));
    }

    @Operation(summary = "预览彻底删除影响", description = "返回文件节点、预计释放空间和业务引用摘要")
    @GetMapping("/api/v1/files/{fileId}/purge-impact")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_WRITE + "')")
    ApiResponse<FilePurgeImpactDto> previewPurgeImpact(@PathVariable UUID fileId) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(fileDeletionService.previewImpact(ownerUserId, fileId, null));
    }

    @Operation(summary = "恢复文件", description = "从回收站恢复已删除的文件")
    @PostMapping("/api/v1/files/{fileId}/restore")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_WRITE + "')")
    ApiResponse<FileNodeDto> restoreFile(@PathVariable UUID fileId) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(fileQueryService.restoreNode(ownerUserId, fileId));
    }

    @Operation(
            summary = "重新处理已有文件",
            description = "重新发布已有文件的索引、缩略图和媒体识别任务，不重复上传对象内容"
    )
    @PostMapping("/api/v1/files/{fileId}/reprocess")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_WRITE + "')")
    ApiResponse<FileNodeDto> reprocessFile(@PathVariable UUID fileId) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(fileUploadSessionService.reprocessExistingFile(ownerUserId, fileId));
    }

    @Operation(summary = "添加收藏", description = "将文件添加到收藏夹")
    @PostMapping("/api/v1/files/{fileId}/favorite")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_WRITE + "')")
    ApiResponse<FileNodeDto> addFavorite(@PathVariable UUID fileId) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(fileManagerService.addFavorite(ownerUserId, fileId));
    }

    @Operation(summary = "取消收藏", description = "将文件从收藏夹移除")
    @DeleteMapping("/api/v1/files/{fileId}/favorite")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_WRITE + "')")
    ApiResponse<Void> removeFavorite(@PathVariable UUID fileId) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        fileManagerService.removeFavorite(ownerUserId, fileId);
        return ApiResponse.success();
    }

    // ─── 批量操作 ───

    @Operation(summary = "批量删除文件", description = "批量将多个文件移入回收站")
    @PostMapping("/api/v1/files/batch/delete")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_WRITE + "')")
    ApiResponse<List<FileNodeDto>> batchDeleteFiles(
            @Valid @RequestBody BatchFileOperationRequest body
    ) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(fileQueryService.batchDeleteNodes(ownerUserId, body.fileIds()));
    }

    @Operation(summary = "批量恢复文件", description = "批量从回收站恢复多个文件")
    @PostMapping("/api/v1/files/batch/restore")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_WRITE + "')")
    ApiResponse<List<FileNodeDto>> batchRestoreFiles(
            @Valid @RequestBody BatchFileOperationRequest body
    ) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(fileQueryService.batchRestoreNodes(ownerUserId, body.fileIds()));
    }

    @Operation(summary = "批量彻底删除", description = "批量从回收站中彻底删除多个文件")
    @DeleteMapping("/api/v1/files/batch/purge")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_WRITE + "')")
    ApiResponse<FilePurgeTaskDto> batchPurgeFiles(
            @Valid @RequestBody BatchFileOperationRequest body,
            @RequestParam(defaultValue = "false") boolean cascade
    ) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        UUID taskId = fileDeletionService.deletePermanentlyBatch(
                ownerUserId,
                body.fileIds(),
                cascade,
                List.of()
        );
        return ApiResponse.success(FilePurgeTaskDto.queued(taskId));
    }

    @Operation(summary = "批量移动文件", description = "批量将多个文件移动到指定目录")
    @PostMapping("/api/v1/files/batch/move")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_WRITE + "')")
    ApiResponse<List<FileNodeDto>> batchMoveFiles(
            @Valid @RequestBody BatchMoveFileNodeRequest body
    ) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(fileQueryService.batchMoveNodes(ownerUserId, body.fileIds(), body.parentId()));
    }

    @Operation(summary = "批量添加收藏", description = "批量将多个文件添加到收藏夹")
    @PostMapping("/api/v1/files/batch/favorite")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_WRITE + "')")
    ApiResponse<List<FileNodeDto>> batchAddFavorites(
            @Valid @RequestBody BatchFileOperationRequest body
    ) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(fileManagerService.batchAddFavorites(ownerUserId, body.fileIds()));
    }

    @Operation(summary = "批量取消收藏", description = "批量将多个文件从收藏夹移除")
    @DeleteMapping("/api/v1/files/batch/favorite")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_WRITE + "')")
    ApiResponse<Void> batchRemoveFavorites(
            @Valid @RequestBody BatchFileOperationRequest body
    ) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        fileManagerService.batchRemoveFavorites(ownerUserId, body.fileIds());
        return ApiResponse.success();
    }

    @Operation(summary = "批量打包下载", description = "将多个文件打包为 ZIP 流式返回")
    @PostMapping("/api/v1/files/batch/download")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_READ + "')")
    void batchDownload(
            @Valid @RequestBody BatchDownloadRequest body,
            HttpServletResponse response
    ) throws IOException {
        response.setContentType("application/zip");
        response.setHeader("Content-Disposition", "attachment; filename=\"omninest-batch.zip\"");
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        fileManagerService.packAsZip(ownerUserId, body.fileIds(), response.getOutputStream());
    }

    @Operation(summary = "获取下载链接", description = "为指定文件生成临时下载链接")
    @GetMapping("/api/v1/files/{fileId}/download-url")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_READ + "')")
    ApiResponse<FileDownloadUrlDto> createDownloadUrl(@PathVariable UUID fileId) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        fileManagerService.recordAccess(ownerUserId, fileId);
        return ApiResponse.success(fileQueryService.createDownloadUrl(ownerUserId, fileId));
    }

    /**
     * 批量签发短期下载地址（封面/缩略等派生资产的前端重签场景）。
     *
     * <p>仅处理当前用户拥有的 FILE 节点；缺失、已删除或非 FILE 节点静默
     * 跳过，不进入结果。不记录访问流水，避免重签风暴污染最近访问。</p>
     */
    @Operation(summary = "批量创建下载链接", description = "为当前用户拥有的文件批量签发短期下载链接")
    @PostMapping("/api/v1/files/download-urls")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_READ + "')")
    ApiResponse<List<FileDownloadUrlDto>> createDownloadUrls(
            @Valid @RequestBody BatchDownloadUrlRequest request) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        List<UUID> fileIds = request.fileIds().stream()
                .map(UUID::fromString)
                .toList();
        return ApiResponse.success(
                List.copyOf(fileQueryService.createDownloadUrls(ownerUserId, fileIds).values()));
    }

    @Operation(summary = "列出共享给我的文件", description = "列出其他用户共享给当前用户的文件")
    @GetMapping("/api/v1/files/shared-with-me")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_READ + "')")
    ApiResponse<PageResponse<FileSharedItemDto>> listSharedWithMe(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "200") int size
    ) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        var items = fileManagerService.listSharedWithMePage(ownerUserId, page, size);
        return ApiResponse.success(PageResponse.of(
                items.getContent(),
                items.getNumber(),
                items.getSize(),
                items.getTotalElements()));
    }

    @Operation(summary = "列出我的分享链接", description = "列出当前用户创建的所有分享链接")
    @GetMapping("/api/v1/files/shares")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_READ + "')")
    ApiResponse<PageResponse<FileShareLinkDto>> listShareLinks(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "200") int size
    ) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        var items = fileManagerService.listMySharesPage(ownerUserId, page, size);
        return ApiResponse.success(PageResponse.of(
                items.getContent(),
                items.getNumber(),
                items.getSize(),
                items.getTotalElements()));
    }

    @Operation(summary = "创建分享链接", description = "为指定文件创建分享链接，可设置密码和过期时间")
    @PostMapping("/api/v1/files/shares")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_WRITE + "')")
    ApiResponse<FileShareLinkDto> createShare(
            @Valid @RequestBody CreateShareLinkRequest body
    ) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(fileManagerService.createShare(ownerUserId, body));
    }

    @Operation(summary = "撤销分享链接", description = "撤销指定的分享链接")
    @DeleteMapping("/api/v1/files/shares/{shareId}")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_WRITE + "')")
    ApiResponse<Void> revokeShare(@PathVariable UUID shareId) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        fileManagerService.revokeShare(ownerUserId, shareId);
        return ApiResponse.success();
    }

    @Operation(summary = "访问分享链接", description = "通过分享令牌访问共享文件，可选密码验证")
    @PostMapping("/api/v1/s/{token}/authorize")
    ApiResponse<ShareAccessSessionDto> authorizeShare(
            @PathVariable String token,
            @RequestBody(required = false) ShareAuthorizationRequest body,
            HttpServletRequest request
    ) {
        String password = body == null ? null : body.password();
        return ApiResponse.success(fileManagerService.issueShareSession(
                token, password, request.getRemoteAddr()));
    }

    @Operation(summary = "访问分享链接", description = "通过短期分享会话访问共享文件")
    @GetMapping("/api/v1/s/{token}")
    ApiResponse<FileShareAccessDto> accessShare(
            @PathVariable String token,
            @RequestHeader(value = "X-OmniNest-Share-Session", required = false) String sessionToken
    ) {
        return ApiResponse.success(fileManagerService.shareAccessSession(token, sessionToken));
    }

    @Operation(summary = "预览分享文件", description = "通过分享令牌预览共享文件内容")
    @GetMapping("/api/v1/s/{token}/preview")
    ApiResponse<FileSharePreviewDto> previewShare(
            @PathVariable String token,
            @RequestHeader(value = "X-OmniNest-Share-Session", required = false) String sessionToken
    ) {
        return ApiResponse.success(fileManagerService.previewShareSession(token, sessionToken));
    }

    @Operation(summary = "接受分享", description = "接受共享文件，将其保存到自己的文件空间")
    @PostMapping("/api/v1/s/{token}/accept")
    ApiResponse<Void> acceptShare(
            @PathVariable String token,
            @RequestHeader(value = "X-OmniNest-Share-Session", required = false) String sessionToken,
            @RequestBody(required = false) AcceptShareRequest body
    ) {
        UUID userId = currentUserContext.requireCurrentUserId();
        fileManagerService.acceptShareSession(userId, token, sessionToken, body);
        return ApiResponse.success();
    }

    @Operation(summary = "获取存储统计", description = "获取当前用户的存储空间使用统计")
    @GetMapping("/api/v1/files/storage-stats")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_READ + "')")
    ApiResponse<FileStorageStatsDto> storageStats() {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(fileStorageMetricsService.userStorageStats(ownerUserId));
    }

    @Operation(summary = "获取上传策略", description = "获取文件上传的策略配置（大小限制、允许类型等）")
    @GetMapping("/api/v1/uploads/policy")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_READ + "')")
    ApiResponse<FileUploadPolicyDto> uploadPolicy() {
        return ApiResponse.success(fileUploadSessionService.uploadPolicy());
    }

    @Operation(summary = "列出上传队列", description = "列出当前用户的上传任务队列")
    @GetMapping("/api/v1/uploads/sessions")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_READ + "')")
    ApiResponse<PageResponse<FileUploadQueueItemDto>> listUploadQueue(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "200") int size
    ) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        var items = fileManagerService.listUploadQueue(ownerUserId);
        return ApiResponse.success(PageResponse.of(items, page, size, items.size()));
    }

    @Operation(summary = "创建上传会话", description = "创建分片上传会话，支持大文件断点续传")
    @PostMapping("/api/v1/uploads/sessions")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_WRITE + "')")
    ApiResponse<FileUploadSessionDto> createUploadSession(
            @Valid @RequestBody CreateFileUploadSessionRequest body
    ) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(fileUploadSessionService.createSession(ownerUserId, body));
    }

    @Operation(summary = "列出上传分片", description = "列出上传会话中各分片的状态")
    @GetMapping("/api/v1/uploads/{uploadId}/parts")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_READ + "')")
    ApiResponse<FileUploadPartsDto> listUploadParts(
            @PathVariable String uploadId
    ) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(fileUploadSessionService.listParts(ownerUserId, uploadId));
    }

    @Operation(summary = "完成分片上传", description = "标记指定分片上传完成并校验 ETag")
    @PostMapping("/api/v1/uploads/{uploadId}/parts/{partNumber}/complete")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_WRITE + "')")
    ApiResponse<FileUploadPartsDto> completeUploadPart(
            @PathVariable String uploadId,
            @PathVariable int partNumber,
            @Valid @RequestBody CompleteFileUploadPartRequest body
    ) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(fileUploadSessionService.completePart(ownerUserId, uploadId, partNumber, body));
    }

    @Operation(summary = "完成上传会话", description = "受理安全扫描后立即返回扫描任务标识，文件节点由扫描通过后创建")
    @PostMapping("/api/v1/uploads/{uploadId}/complete")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_WRITE + "')")
    ApiResponse<FileUploadCompleteResultDto> completeUploadSession(
            @PathVariable String uploadId,
            @Valid @RequestBody(required = false) CompleteFileUploadRequest body
    ) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(fileUploadSessionService.completeSession(ownerUserId, uploadId, body));
    }

    @Operation(summary = "取消上传会话", description = "取消指定的上传会话并清理临时数据")
    @DeleteMapping("/api/v1/uploads/{uploadId}")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_WRITE + "')")
    ApiResponse<Void> cancelUploadSession(@PathVariable String uploadId) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        fileUploadSessionService.cancelSession(ownerUserId, uploadId);
        return ApiResponse.success();
    }

    @Operation(summary = "获取分片上传地址", description = "获取指定分片的预签名上传地址")
    @GetMapping("/api/v1/uploads/{uploadId}/parts/{partNumber}/url")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_READ + "')")
    ApiResponse<FileUploadPartDto> getUploadPartUrl(
            @PathVariable String uploadId,
            @PathVariable int partNumber
    ) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(fileUploadSessionService.getPartUrl(ownerUserId, uploadId, partNumber));
    }

    @Operation(summary = "延长上传会话", description = "延长指定上传会话的过期时间")
    @PostMapping("/api/v1/uploads/{uploadId}/extend")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_WRITE + "')")
    ApiResponse<FileUploadSessionDto> extendUploadSession(@PathVariable String uploadId) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(fileUploadSessionService.extendSession(ownerUserId, uploadId));
    }

    @Operation(summary = "列出离线下载任务", description = "列出当前用户的离线下载任务")
    @GetMapping("/api/v1/offline-downloads")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_READ + "')")
    ApiResponse<PageResponse<OfflineDownloadTaskDto>> listOfflineDownloads(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "200") int size
    ) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        var items = offlineDownloadRequestService.listTasks(ownerUserId);
        return ApiResponse.success(PageResponse.of(items, page, size, items.size()));
    }

    @Operation(summary = "查询离线下载任务", description = "按 ID 查询单个离线下载任务")
    @GetMapping("/api/v1/offline-downloads/{taskId}")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_READ + "')")
    ApiResponse<OfflineDownloadTaskDto> getOfflineDownload(@PathVariable UUID taskId) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(offlineDownloadRequestService.getTask(ownerUserId, taskId));
    }

    @Operation(summary = "创建离线下载任务", description = "提交离线下载任务，服务端异步下载文件")
    @PostMapping("/api/v1/offline-downloads")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_WRITE + "')")
    ApiResponse<OfflineDownloadTaskDto> createOfflineDownload(
            @Valid @RequestBody CreateOfflineDownloadRequest body
    ) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(offlineDownloadRequestService.createTask(ownerUserId, body));
    }

    @Operation(summary = "取消离线下载", description = "取消指定的离线下载任务")
    @DeleteMapping("/api/v1/offline-downloads/{taskId}")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_WRITE + "')")
    ApiResponse<Void> cancelOfflineDownload(@PathVariable UUID taskId) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        offlineDownloadRequestService.cancelTask(ownerUserId, taskId);
        return ApiResponse.success();
    }

    @Operation(summary = "列出外部存储", description = "列出当前用户关联的外部存储账户")
    @GetMapping("/api/v1/external-storages")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_READ + "')")
    ApiResponse<PageResponse<ExternalStorageAccountDto>> listExternalStorages(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "200") int size
    ) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        var items = fileManagerService.listExternalAccounts(ownerUserId);
        return ApiResponse.success(PageResponse.of(items, page, size, items.size()));
    }

    @Operation(summary = "创建外部存储", description = "关联一个新的外部存储账户")
    @PostMapping("/api/v1/external-storages")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_WRITE + "')")
    ApiResponse<ExternalStorageAccountDto> createExternalStorage(
            @Valid @RequestBody CreateExternalStorageRequest body
    ) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(fileManagerService.createExternalAccount(ownerUserId, body));
    }

    @Operation(summary = "更新外部存储", description = "更新指定外部存储账户的配置信息")
    @PutMapping("/api/v1/external-storages/{accountId}")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_WRITE + "')")
    ApiResponse<ExternalStorageAccountDto> updateExternalStorage(
            @PathVariable UUID accountId,
            @Valid @RequestBody UpdateExternalStorageRequest body
    ) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(fileManagerService.updateExternalAccount(ownerUserId, accountId, body));
    }

    @Operation(summary = "禁用外部存储", description = "禁用指定的外部存储账户")
    @DeleteMapping("/api/v1/external-storages/{accountId}")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_WRITE + "')")
    ApiResponse<Void> disableExternalStorage(@PathVariable UUID accountId) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        fileManagerService.disableExternalAccount(ownerUserId, accountId);
        return ApiResponse.success();
    }

    @Operation(summary = "删除外部存储", description = "永久删除指定的外部存储账户及其配置")
    @DeleteMapping("/api/v1/external-storages/{accountId}/permanent")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_WRITE + "')")
    ApiResponse<Void> deleteExternalStorage(@PathVariable UUID accountId) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        fileManagerService.deleteExternalAccount(ownerUserId, accountId);
        return ApiResponse.success();
    }

    // ─── 共享管理 ───

    @Operation(summary = "切换共享状态", description = "切换文件的共享开关状态")
    @PutMapping("/api/v1/files/{fileId}/shared")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_WRITE + "')")
    ApiResponse<Void> toggleShared(@PathVariable UUID fileId) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        fileManagerService.toggleShared(ownerUserId, fileId);
        return ApiResponse.success();
    }

    @Operation(summary = "递归切换共享状态", description = "递归切换文件夹及其子项的共享状态")
    @PutMapping("/api/v1/files/{fileId}/shared/recursive")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_WRITE + "')")
    ApiResponse<Void> toggleSharedRecursive(
            @PathVariable UUID fileId,
            @RequestParam boolean shared
    ) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        fileManagerService.toggleSharedRecursive(ownerUserId, fileId, shared);
        return ApiResponse.success();
    }

    @Operation(summary = "列出共享文件", description = "列出当前用户可见的共享文件，支持分页")
    @GetMapping("/api/v1/files/shared")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_READ + "')")
    ApiResponse<PageResponse<SharedFileDto>> listSharedFiles(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "200") int size
    ) {
        UUID userId = currentUserContext.requireCurrentUserId();
        var files = fileManagerService.listSharedFilesPage(userId, page, size);
        return ApiResponse.success(PageResponse.of(
                files.getContent(),
                files.getNumber(),
                files.getSize(),
                files.getTotalElements()));
    }

    // ─── 权限管理 ───

    @Operation(summary = "设置全局权限", description = "设置文件的默认全局访问权限")
    @PutMapping("/api/v1/files/{fileId}/permissions/default")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_WRITE + "')")
    ApiResponse<Void> setGlobalPermission(
            @PathVariable UUID fileId,
            @RequestBody PermissionRequest request
    ) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        fileManagerService.setGlobalPermission(ownerUserId, fileId, request);
        return ApiResponse.success();
    }

    @Operation(summary = "设置用户权限", description = "为指定用户设置文件的访问权限")
    @PutMapping("/api/v1/files/{fileId}/permissions/users/{granteeUserId}")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_WRITE + "')")
    ApiResponse<Void> setUserPermission(
            @PathVariable UUID fileId,
            @PathVariable UUID granteeUserId,
            @RequestBody PermissionRequest request
    ) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        fileManagerService.setUserPermission(ownerUserId, fileId, granteeUserId, request);
        return ApiResponse.success();
    }

    @Operation(summary = "移除用户权限", description = "移除指定用户对文件的访问权限")
    @DeleteMapping("/api/v1/files/{fileId}/permissions/users/{granteeUserId}")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_WRITE + "')")
    ApiResponse<Void> removeUserPermission(
            @PathVariable UUID fileId,
            @PathVariable UUID granteeUserId
    ) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        fileManagerService.removeUserPermission(ownerUserId, fileId, granteeUserId);
        return ApiResponse.success();
    }

    @Operation(summary = "列出权限配置", description = "列出指定文件的所有权限配置")
    @GetMapping("/api/v1/files/{fileId}/permissions")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_READ + "')")
    ApiResponse<List<FilePermissionDto>> listPermissions(@PathVariable UUID fileId) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(fileManagerService.listPermissions(ownerUserId, fileId));
    }

    @Operation(summary = "获取共享文件下载链接", description = "为共享文件生成临时下载链接")
    @GetMapping("/api/v1/files/{fileId}/download-url/shared")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_READ + "')")
    ApiResponse<FileDownloadUrlDto> getSharedDownloadUrl(@PathVariable UUID fileId) {
        UUID userId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(fileQueryService.createDownloadUrlForShared(userId, fileId));
    }
}
