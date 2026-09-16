package com.omninest.modules.file.controller;

import com.omninest.common.api.ApiResponse;
import com.omninest.common.api.PageResponse;
import com.omninest.common.security.CurrentUserContext;
import com.omninest.common.security.Permissions;
import com.omninest.modules.file.dto.CreateImportTaskRequest;
import com.omninest.modules.file.dto.ExternalFileListDto;
import com.omninest.modules.file.dto.ExternalSpaceDto;
import com.omninest.modules.file.dto.ImportTaskDto;
import com.omninest.modules.file.service.ExternalStorageService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * 外部存储 API。远程源只读浏览与导入，不提供远端写操作。
 *
 * @author OmniNest
 */
@RestController
@RequiredArgsConstructor
@Tag(name = "外部存储", description = "远程来源浏览与导入到受管存储")
public class ExternalStorageController {
    private final ExternalStorageService externalStorageService;
    private final CurrentUserContext currentUserContext;

    @Operation(summary = "列出连接器目录", description = "返回可接入的远程存储类型")
    @GetMapping("/api/v1/external-connectors")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_READ + "')")
    ApiResponse<List<com.omninest.modules.file.dto.ExternalStorageConnectorDto>> listConnectors() {
        return ApiResponse.success(externalStorageService.listConnectors());
    }

    @Operation(summary = "测试连接", description = "验证外部存储账户是否可连通")
    @PostMapping("/api/v1/external-storages/{accountId}/test")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_READ + "')")
    ApiResponse<com.omninest.modules.file.dto.ExternalStorageTestResultDto> testConnection(
            @PathVariable UUID accountId
    ) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(externalStorageService.testConnection(ownerUserId, accountId));
    }

    @Operation(summary = "浏览外部存储", description = "浏览指定外部存储账户中的文件和目录")
    @GetMapping("/api/v1/external-storages/{accountId}/browse")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_READ + "')")
    ApiResponse<ExternalFileListDto> browse(
            @PathVariable UUID accountId,
            @RequestParam(required = false, defaultValue = "/") String path
    ) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(externalStorageService.browse(ownerUserId, accountId, path));
    }

    @Operation(summary = "获取空间使用情况", description = "查询指定外部存储账户的空间使用量和配额")
    @GetMapping("/api/v1/external-storages/{accountId}/space")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_READ + "')")
    ApiResponse<ExternalSpaceDto> getSpaceUsage(@PathVariable UUID accountId) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(externalStorageService.getSpaceUsage(ownerUserId, accountId));
    }

    @Operation(summary = "获取文件系统信息", description = "获取指定外部存储账户的文件系统元信息")
    @GetMapping("/api/v1/external-storages/{accountId}/info")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_READ + "')")
    ApiResponse<Map<String, Object>> getFsInfo(@PathVariable UUID accountId) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(externalStorageService.getFsInfo(ownerUserId, accountId));
    }

    @Operation(summary = "创建导入任务", description = "从外部存储导入文件到本地存储")
    @PostMapping("/api/v1/external-storages/{accountId}/import")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_WRITE + "')")
    ApiResponse<ImportTaskDto> createImportTask(
            @PathVariable UUID accountId,
            @Valid @RequestBody CreateImportTaskRequest body
    ) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(externalStorageService.createImportTask(ownerUserId, accountId, body));
    }

    @Operation(summary = "列出导入任务", description = "列出当前用户的所有导入任务")
    @GetMapping("/api/v1/external-storages/import-tasks")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_READ + "')")
    ApiResponse<PageResponse<ImportTaskDto>> listImportTasks() {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        List<ImportTaskDto> items = externalStorageService.listImportTasks(ownerUserId);
        return ApiResponse.success(PageResponse.of(items, 0, 50, items.size()));
    }

    @Operation(summary = "取消导入任务", description = "取消指定的导入任务")
    @DeleteMapping("/api/v1/external-storages/import-tasks/{taskId}")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_WRITE + "')")
    ApiResponse<Void> cancelImportTask(@PathVariable UUID taskId) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        externalStorageService.cancelImportTask(ownerUserId, taskId);
        return ApiResponse.success();
    }
}
