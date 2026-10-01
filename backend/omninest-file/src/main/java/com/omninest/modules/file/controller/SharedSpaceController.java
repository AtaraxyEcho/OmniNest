package com.omninest.modules.file.controller;

import com.omninest.common.api.ApiResponse;
import com.omninest.common.api.PageResponse;
import com.omninest.common.config.RuntimeConfigCommand;
import com.omninest.common.security.CurrentUserContext;
import com.omninest.common.security.Permissions;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.dto.CreateFolderRequest;
import com.omninest.modules.file.dto.FileNodeDto;
import com.omninest.modules.file.service.FileNodeSupport;
import com.omninest.modules.file.dto.MoveToSpaceRequest;
import com.omninest.modules.file.dto.RenameFileNodeRequest;
import com.omninest.modules.file.dto.SharedSpaceUsageDto;
import com.omninest.modules.file.service.SharedSpaceQuotaService;
import com.omninest.modules.file.service.SharedSpaceService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import java.util.List;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * 共享空间控制器，提供共享空间的文件浏览、创建、删除和跨空间移动接口。
 */
@Tag(name = "共享空间", description = "共享空间文件管理接口")
@RestController
@RequestMapping("/api/v1/shared-space")
@RequiredArgsConstructor
public class SharedSpaceController {

    private final SharedSpaceService sharedSpaceService;
    private final FileNodeSupport fileNodeSupport;
    private final SharedSpaceQuotaService quotaService;
    private final RuntimeConfigCommand runtimeConfigCommand;
    private final CurrentUserContext currentUserContext;

    @Operation(summary = "浏览共享空间目录")
    @GetMapping("/files")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_READ + "')")
    public ApiResponse<PageResponse<FileNodeDto>> listFiles(
            @RequestParam(required = false) UUID parentId,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "100") int size) {
        UUID operatorId = currentUserContext.requireCurrentUserId();
        var files = sharedSpaceService.listSharedSpaceFilesPage(parentId, operatorId, page, size);
        List<FileNodeDto> dtos = files.getContent().stream().map(this::toDto).toList();
        return ApiResponse.success(PageResponse.of(dtos, files.getNumber(), files.getSize(), files.getTotalElements()));
    }

    @Operation(summary = "在共享空间创建文件夹")
    @PostMapping("/folders")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_WRITE + "')")
    public ApiResponse<FileNodeDto> createFolder(
            @RequestParam(required = false) UUID parentId,
            @RequestBody @Valid CreateFolderRequest request) {
        FileNode folder = sharedSpaceService.createFolder(parentId, request.name(), currentUserContext.requireCurrentUserId());
        return ApiResponse.success(toDto(folder));
    }

    @Operation(summary = "重命名共享空间文件")
    @PatchMapping("/files/{fileId}/rename")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_WRITE + "')")
    public ApiResponse<FileNodeDto> renameFile(
            @PathVariable UUID fileId,
            @RequestBody @Valid RenameFileNodeRequest request) {
        FileNode node = sharedSpaceService.renameSharedFile(
                fileId,
                request,
                currentUserContext.requireCurrentUserId());
        return ApiResponse.success(toDto(node));
    }

    @Operation(summary = "移动文件到共享空间")
    @PostMapping("/move-to-shared")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_WRITE + "')")
    public ApiResponse<Void> moveToSharedSpace(@RequestBody @Valid MoveToSpaceRequest request) {
        sharedSpaceService.moveToSharedSpace(request.fileNodeId(), currentUserContext.requireCurrentUserId());
        return ApiResponse.success();
    }

    @Operation(summary = "从共享空间移回个人空间")
    @PostMapping("/move-to-personal")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_WRITE + "')")
    public ApiResponse<Void> moveToPersonalSpace(@RequestBody @Valid MoveToSpaceRequest request) {
        sharedSpaceService.moveToPersonalSpace(request.fileNodeId(), currentUserContext.requireCurrentUserId());
        return ApiResponse.success();
    }

    @Operation(summary = "删除共享空间文件")
    @DeleteMapping("/files/{fileId}")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_WRITE + "')")
    public ApiResponse<Void> deleteSharedFile(@PathVariable UUID fileId) {
        sharedSpaceService.deleteSharedFile(fileId, currentUserContext.requireCurrentUserId());
        return ApiResponse.success();
    }

    @Operation(summary = "获取共享空间使用情况")
    @GetMapping("/usage")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_READ + "')")
    public ApiResponse<SharedSpaceUsageDto> getUsage() {
        return ApiResponse.success(quotaService.getUsageDto());
    }

    @Operation(summary = "管理员：更新共享空间配置")
    @PutMapping("/config")
    @PreAuthorize("hasAuthority('" + Permissions.SYSTEM_CONFIG_MANAGE + "')")
    public ApiResponse<Void> updateConfig(@RequestBody @Valid SharedSpaceConfigRequest request) {
        UUID operatorId = currentUserContext.requireCurrentUserId();
        if (request.maxBytes() != null && !request.maxBytes().isBlank()) {
            runtimeConfigCommand.updateValue("share.max-bytes", request.maxBytes(),
                    "管理员更新共享空间容量", operatorId);
        }
        if (request.enabled() != null && !request.enabled().isBlank()) {
            runtimeConfigCommand.updateValue("share.enabled", request.enabled(),
                    "管理员更新共享空间启用状态", operatorId);
        }
        return ApiResponse.success();
    }

    @Operation(summary = "管理员：设置角色权限")
    @PutMapping("/permissions/{roleId}")
    @PreAuthorize("hasAuthority('" + Permissions.SYSTEM_CONFIG_MANAGE + "')")
    public ApiResponse<Void> setRolePermission(
            @PathVariable UUID roleId,
            @RequestBody @Valid SharedSpacePermissionRequest request) {
        sharedSpaceService.setRolePermission(
                roleId, request.canBrowse(), request.canUpload(),
                request.canDownload(), request.canDeleteOwn(), request.canDeleteAny(),
                request.canMoveTo(), request.canMoveFrom(), request.canCreateFolder());
        return ApiResponse.success();
    }

    private FileNodeDto toDto(FileNode node) {
        return fileNodeSupport.toNodeDto(node);
    }

    /**
     * 共享空间配置更新请求。
     */
    public record SharedSpaceConfigRequest(
            String maxBytes,
            String enabled
    ) {}

    /**
     * 共享空间权限设置请求。
     */
    public record SharedSpacePermissionRequest(
            Boolean canBrowse,
            Boolean canUpload,
            Boolean canDownload,
            Boolean canDeleteOwn,
            Boolean canDeleteAny,
            Boolean canMoveTo,
            Boolean canMoveFrom,
            Boolean canCreateFolder
    ) {}
}
