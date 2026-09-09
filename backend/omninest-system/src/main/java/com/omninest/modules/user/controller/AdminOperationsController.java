package com.omninest.modules.user.controller;

import com.omninest.common.api.ApiResponse;
import com.omninest.common.api.PageResponse;
import com.omninest.common.security.CurrentUserContext;
import com.omninest.common.security.Permissions;
import com.omninest.modules.configcenter.dto.ConfigEntryDto;
import com.omninest.modules.user.dto.AdminOperationsDto;
import com.omninest.modules.user.service.AdminOperationsPagingService;
import com.omninest.modules.user.service.AdminOperationsService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import java.util.List;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@Tag(name = "运维管理", description = "系统运维操作与监控")
@RestController
@RequiredArgsConstructor
public class AdminOperationsController {
    private final AdminOperationsService adminOperationsService;
    private final AdminOperationsPagingService adminOperationsPagingService;
    private final CurrentUserContext currentUserContext;

    @Operation(summary = "获取角色详情管理视图")
    @GetMapping("/api/v1/admin/roles/detail")
    @PreAuthorize("hasAuthority('" + Permissions.SYSTEM_CONFIG_READ + "')")
    ApiResponse<AdminOperationsDto.RoleManagementView> roles() {
        return ApiResponse.success(adminOperationsService.roles());
    }

    @Operation(summary = "更新角色权限配置")
    @PutMapping("/api/v1/admin/roles/{roleCode}/permissions")
    @PreAuthorize("hasAuthority('" + Permissions.SYSTEM_CONFIG_MANAGE + "')")
    ApiResponse<AdminOperationsDto.RoleDetail> updateRolePermissions(
            @PathVariable String roleCode,
            @Valid @RequestBody AdminOperationsDto.UpdateRolePermissionsRequest request
    ) {
        return ApiResponse.success(
                adminOperationsService.updateRolePermissions(currentUserContext.requireCurrentUserId(), roleCode, request)
        );
    }

    @Operation(summary = "获取配置项管理视图")
    @GetMapping("/api/v1/admin/configs/detail")
    @PreAuthorize("hasAuthority('" + Permissions.SYSTEM_CONFIG_READ + "')")
    ApiResponse<AdminOperationsDto.ConfigManagementView> configs() {
        return ApiResponse.success(adminOperationsService.configs());
    }

    @Operation(summary = "更新系统配置项")
    @PutMapping("/api/v1/admin/configs/detail/{key}")
    @PreAuthorize("hasAuthority('" + Permissions.SYSTEM_CONFIG_MANAGE + "')")
    ApiResponse<ConfigEntryDto> updateConfig(
            @PathVariable String key,
            @Valid @RequestBody AdminOperationsDto.UpdateConfigRequest request
    ) {
        return ApiResponse.success(
                adminOperationsService.updateConfig(currentUserContext.requireCurrentUserId(), key, request)
        );
    }

    @Operation(summary = "获取任务管理视图")
    @GetMapping("/api/v1/admin/tasks")
    @PreAuthorize("hasAuthority('" + Permissions.TASK_ADMIN + "')")
    ApiResponse<AdminOperationsDto.TaskManagementView> tasks() {
        return ApiResponse.success(adminOperationsService.tasks());
    }

    @Operation(summary = "分页查询后台任务")
    @GetMapping("/api/v1/admin/tasks/page")
    @PreAuthorize("hasAuthority('" + Permissions.TASK_ADMIN + "')")
    ApiResponse<PageResponse<AdminOperationsDto.TaskRecordItem>> taskPage(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "25") int size,
            @RequestParam(defaultValue = "") String status,
            @RequestParam(defaultValue = "") String taskType,
            @RequestParam(defaultValue = "") String query,
            @RequestParam(defaultValue = "updatedAt") String sort,
            @RequestParam(defaultValue = "desc") String dir
    ) {
        return ApiResponse.success(adminOperationsPagingService.taskPage(page, size, status, taskType, query, sort, dir));
    }

    @Operation(summary = "重试失败任务")
    @PostMapping("/api/v1/admin/tasks/{taskId}/retry")
    @PreAuthorize("hasAuthority('" + Permissions.SYSTEM_CONFIG_MANAGE + "')")
    ApiResponse<AdminOperationsDto.TaskRecordItem> retryTask(@PathVariable UUID taskId) {
        return ApiResponse.success(adminOperationsService.retryTask(currentUserContext.requireCurrentUserId(), taskId));
    }

    @Operation(summary = "获取系统日志视图")
    @GetMapping("/api/v1/admin/logs")
    @PreAuthorize("hasAuthority('" + Permissions.SYSTEM_CONFIG_READ + "')")
    ApiResponse<AdminOperationsDto.LogManagementView> logs() {
        return ApiResponse.success(adminOperationsService.logs());
    }

    @Operation(summary = "分页查询操作审计日志")
    @GetMapping("/api/v1/admin/logs/page")
    @PreAuthorize("hasAuthority('" + Permissions.SYSTEM_CONFIG_READ + "')")
    ApiResponse<PageResponse<AdminOperationsDto.AuditLogItem>> logPage(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "25") int size,
            @RequestParam(defaultValue = "") String action,
            @RequestParam(defaultValue = "") String query,
            @RequestParam(defaultValue = "createdAt") String sort,
            @RequestParam(defaultValue = "desc") String dir
    ) {
        return ApiResponse.success(adminOperationsPagingService.logPage(page, size, action, query, sort, dir));
    }

    @Operation(summary = "获取系统监控数据")
    @GetMapping("/api/v1/admin/monitoring")
    @PreAuthorize("hasAuthority('" + Permissions.SYSTEM_CONFIG_READ + "')")
    ApiResponse<AdminOperationsDto.MonitoringView> monitoring() {
        return ApiResponse.success(adminOperationsService.monitoring());
    }

    @Operation(summary = "获取存储管理视图")
    @GetMapping("/api/v1/admin/storage")
    @PreAuthorize("hasAuthority('" + Permissions.SYSTEM_CONFIG_READ + "')")
    ApiResponse<AdminOperationsDto.StorageManagementView> storage() {
        return ApiResponse.success(adminOperationsService.storage());
    }

    @Operation(summary = "获取外部存储管理视图")
    @GetMapping("/api/v1/admin/external-storage")
    @PreAuthorize("hasAuthority('" + Permissions.SYSTEM_CONFIG_READ + "')")
    ApiResponse<AdminOperationsDto.ExternalStorageView> externalStorage() {
        return ApiResponse.success(adminOperationsService.externalStorage());
    }

    @Operation(summary = "创建外部存储配置")
    @PostMapping("/api/v1/admin/external-storage")
    @PreAuthorize("hasAuthority('" + Permissions.SYSTEM_CONFIG_MANAGE + "')")
    ApiResponse<AdminOperationsDto.ExternalStorageItem> createExternalStorage(
            @Valid @RequestBody AdminOperationsDto.CreateExternalStorageRequest request
    ) {
        return ApiResponse.success(
                adminOperationsService.createExternalStorage(currentUserContext.requireCurrentUserId(), request)
        );
    }

    @Operation(summary = "更新外部存储状态")
    @PatchMapping("/api/v1/admin/external-storage/{id}/status")
    @PreAuthorize("hasAuthority('" + Permissions.SYSTEM_CONFIG_MANAGE + "')")
    ApiResponse<AdminOperationsDto.ExternalStorageItem> updateExternalStorageStatus(
            @PathVariable UUID id,
            @Valid @RequestBody AdminOperationsDto.UpdateExternalStorageStatusRequest request
    ) {
        return ApiResponse.success(
                adminOperationsService.updateExternalStorageStatus(currentUserContext.requireCurrentUserId(), id, request)
        );
    }

    // ── 会话管理 ──────────────────────────────────────────────────────────

    @Operation(summary = "获取所有会话列表")
    @GetMapping("/api/v1/admin/sessions")
    @PreAuthorize("hasAuthority('" + Permissions.SYSTEM_CONFIG_READ + "')")
    ApiResponse<AdminOperationsDto.SessionManagementView> allSessions() {
        return ApiResponse.success(adminOperationsService.allSessions());
    }

    @Operation(summary = "分页查询系统会话")
    @GetMapping("/api/v1/admin/sessions/page")
    @PreAuthorize("hasAuthority('" + Permissions.SYSTEM_CONFIG_READ + "')")
    ApiResponse<PageResponse<AdminOperationsDto.SessionItem>> sessionPage(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "25") int size,
            @RequestParam(defaultValue = "") String status,
            @RequestParam(defaultValue = "") String platform,
            @RequestParam(defaultValue = "") String query,
            @RequestParam(defaultValue = "lastActiveAt") String sort,
            @RequestParam(defaultValue = "desc") String dir
    ) {
        return ApiResponse.success(adminOperationsPagingService.sessionPage(page, size, status, platform, query, sort, dir));
    }

    @Operation(summary = "撤销指定会话")
    @PostMapping("/api/v1/admin/sessions/{sessionId}/revoke")
    @PreAuthorize("hasAuthority('" + Permissions.SYSTEM_CONFIG_MANAGE + "')")
    ApiResponse<Void> revokeSession(@PathVariable UUID sessionId) {
        adminOperationsService.revokeSession(currentUserContext.requireCurrentUserId(), sessionId);
        return ApiResponse.success(null);
    }

    @Operation(summary = "清理过期或已撤销会话")
    @DeleteMapping("/api/v1/admin/sessions/cleanup")
    @PreAuthorize("hasAuthority('" + Permissions.SYSTEM_CONFIG_MANAGE + "')")
    ApiResponse<Integer> cleanupSessions(@RequestParam(defaultValue = "30") int retentionDays) {
        return ApiResponse.success(adminOperationsService.cleanupSessions(
                currentUserContext.requireCurrentUserId(), retentionDays));
    }

    // ── 登录日志 ──────────────────────────────────────────────────────────

    @Operation(summary = "获取登录审计日志")
    @GetMapping("/api/v1/admin/login-audit")
    @PreAuthorize("hasAuthority('" + Permissions.SYSTEM_CONFIG_READ + "')")
    ApiResponse<AdminOperationsDto.LoginAuditView> loginAuditLogs() {
        return ApiResponse.success(adminOperationsService.loginAuditLogs());
    }

    @Operation(summary = "分页查询登录审计日志")
    @GetMapping("/api/v1/admin/login-audit/page")
    @PreAuthorize("hasAuthority('" + Permissions.SYSTEM_CONFIG_READ + "')")
    ApiResponse<PageResponse<AdminOperationsDto.LoginAuditItem>> loginAuditPage(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "25") int size,
            @RequestParam(defaultValue = "") String result,
            @RequestParam(defaultValue = "") String platform,
            @RequestParam(defaultValue = "") String query,
            @RequestParam(defaultValue = "createdAt") String sort,
            @RequestParam(defaultValue = "desc") String dir
    ) {
        return ApiResponse.success(adminOperationsPagingService.loginAuditPage(page, size, result, platform, query, sort, dir));
    }

    @Operation(summary = "清理操作审计日志")
    @DeleteMapping("/api/v1/admin/logs/audit/cleanup")
    @PreAuthorize("hasAuthority('" + Permissions.SYSTEM_CONFIG_MANAGE + "')")
    ApiResponse<Integer> cleanupAuditLogs(@RequestParam(defaultValue = "30") int retentionDays) {
        return ApiResponse.success(adminOperationsService.cleanupAuditLogs(
                currentUserContext.requireCurrentUserId(), retentionDays));
    }

    @Operation(summary = "清理登录审计日志")
    @DeleteMapping("/api/v1/admin/login-audit/cleanup")
    @PreAuthorize("hasAuthority('" + Permissions.SYSTEM_CONFIG_MANAGE + "')")
    ApiResponse<Integer> cleanupLoginAuditLogs(@RequestParam(defaultValue = "30") int retentionDays) {
        return ApiResponse.success(adminOperationsService.cleanupLoginAuditLogs(
                currentUserContext.requireCurrentUserId(), retentionDays));
    }
}
