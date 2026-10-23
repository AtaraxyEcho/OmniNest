package com.omninest.modules.file.controller;

import com.omninest.common.api.ApiResponse;
import com.omninest.common.api.PageResponse;
import com.omninest.common.security.CurrentUserContext;
import com.omninest.common.security.Permissions;
import com.omninest.modules.file.dto.StorageLocationDtos.CreateStorageLocationRequest;
import com.omninest.modules.file.dto.StorageLocationDtos.StorageLocationDescriptor;
import com.omninest.modules.file.dto.StorageLocationDtos.StorageLocationDto;
import com.omninest.modules.file.dto.StorageLocationDtos.StorageDirectoryDto;
import com.omninest.modules.file.dto.StorageLocationDtos.UpdateStorageLocationRequest;
import com.omninest.modules.file.dto.StorageLocationDtos.TrustedMountDto;
import com.omninest.modules.file.service.StorageLocationService;
import com.omninest.modules.file.service.StorageDirectoryService;
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
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * 本地只读存储位置管理接口。
 *
 * @author OmniNest
 */
@RestController
@RequiredArgsConstructor
@Tag(name = "存储位置", description = "本地只读媒体挂载与作用域管理")
public class StorageLocationController {

    private final StorageLocationService storageLocationService;
    private final StorageDirectoryService storageDirectoryService;
    private final CurrentUserContext currentUserContext;

    @Operation(summary = "列出全部存储位置")
    @GetMapping("/api/v1/admin/storage/locations")
    @PreAuthorize("hasAuthority('" + Permissions.SYSTEM_CONFIG_READ + "')")
    ApiResponse<List<StorageLocationDto>> listAll() {
        return ApiResponse.success(storageLocationService.listAll());
    }

    @Operation(summary = "列出部署可信挂载")
    @GetMapping("/api/v1/admin/storage/mounts")
    @PreAuthorize("hasAuthority('" + Permissions.SYSTEM_CONFIG_READ + "')")
    ApiResponse<List<TrustedMountDto>> listTrustedMounts() {
        return ApiResponse.success(storageLocationService.listTrustedMounts());
    }

    @Operation(summary = "浏览部署可信挂载内的安全目录")
    @GetMapping("/api/v1/admin/storage/mounts/{mountKey}/directories")
    @PreAuthorize("hasAuthority('" + Permissions.SYSTEM_CONFIG_MANAGE + "')")
    ApiResponse<PageResponse<StorageDirectoryDto>> listTrustedMountDirectories(
            @PathVariable String mountKey,
            @RequestParam(required = false) String parent,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "100") int size
    ) {
        return ApiResponse.success(storageDirectoryService.listMountChildren(mountKey, parent, page, size));
    }

    @Operation(summary = "创建本地只读存储位置")
    @PostMapping("/api/v1/admin/storage/locations")
    @PreAuthorize("hasAuthority('" + Permissions.SYSTEM_CONFIG_MANAGE + "')")
    ApiResponse<StorageLocationDto> create(@Valid @RequestBody CreateStorageLocationRequest request) {
        return ApiResponse.success(storageLocationService.create(
                currentUserContext.requireCurrentUserId(),
                request
        ));
    }

    @Operation(summary = "更新本地只读存储位置")
    @PutMapping("/api/v1/admin/storage/locations/{locationId}")
    @PreAuthorize("hasAuthority('" + Permissions.SYSTEM_CONFIG_MANAGE + "')")
    ApiResponse<StorageLocationDto> update(
            @PathVariable UUID locationId,
            @Valid @RequestBody UpdateStorageLocationRequest request
    ) {
        return ApiResponse.success(storageLocationService.update(
                currentUserContext.requireCurrentUserId(), locationId, request));
    }

    @Operation(summary = "删除未被引用的存储位置")
    @DeleteMapping("/api/v1/admin/storage/locations/{locationId}")
    @PreAuthorize("hasAuthority('" + Permissions.SYSTEM_CONFIG_MANAGE + "')")
    ApiResponse<Void> delete(@PathVariable UUID locationId) {
        storageLocationService.delete(currentUserContext.requireCurrentUserId(), locationId);
        return ApiResponse.success();
    }

    @Operation(summary = "列出当前用户可用的影视库存储位置")
    @GetMapping("/api/v1/storage/locations/accessible")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_LIBRARY_MANAGE + "')")
    ApiResponse<List<StorageLocationDescriptor>> listAccessible() {
        return ApiResponse.success(storageLocationService.listAccessible(
                currentUserContext.requireCurrentUserId()
        ));
    }

    @Operation(summary = "浏览存储位置内的安全目录")
    @GetMapping("/api/v1/storage/locations/{locationId}/directories")
    @PreAuthorize("hasAuthority('" + Permissions.MEDIA_LIBRARY_MANAGE + "')")
    ApiResponse<PageResponse<StorageDirectoryDto>> listDirectories(
            @PathVariable UUID locationId,
            @RequestParam(required = false) String parent,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "100") int size
    ) {
        return ApiResponse.success(storageDirectoryService.listChildren(
                currentUserContext.requireCurrentUserId(),
                locationId,
                parent,
                page,
                size
        ));
    }
}
