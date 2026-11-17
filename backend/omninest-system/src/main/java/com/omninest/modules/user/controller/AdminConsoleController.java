package com.omninest.modules.user.controller;

import com.omninest.common.api.ApiResponse;
import com.omninest.common.audit.AdminAuditRecorder;
import com.omninest.common.security.CurrentUserContext;
import com.omninest.common.security.FreshAdminActorVerifier;
import com.omninest.common.security.Permissions;
import com.omninest.modules.user.dto.AdminAnalyticsDto;
import com.omninest.modules.user.dto.AdminConsoleSummaryDto;
import com.omninest.modules.user.service.AdminConsoleService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@Tag(name = "管理控制台", description = "管理控制台概览数据")
@RestController
@RequiredArgsConstructor
public class AdminConsoleController {
    private final AdminConsoleService adminConsoleService;
    private final CurrentUserContext currentUserContext;
    private final FreshAdminActorVerifier adminActorGuard;
    private final AdminAuditRecorder adminAuditRecorder;

    @Operation(summary = "获取管理控制台概览数据")
    @GetMapping("/api/v1/admin/summary")
    @PreAuthorize("hasAnyAuthority('" + Permissions.SYSTEM_USER_READ + "','" + Permissions.SYSTEM_CONFIG_READ + "')")
    ApiResponse<AdminConsoleSummaryDto> summary() {
        return ApiResponse.success(adminConsoleService.summary());
    }

    @Operation(summary = "获取系统分析统计")
    @GetMapping("/api/v1/admin/analytics")
    @PreAuthorize("hasAnyAuthority('" + Permissions.SYSTEM_USER_READ + "','" + Permissions.SYSTEM_CONFIG_READ + "')")
    ApiResponse<AdminAnalyticsDto> analytics(@RequestParam(defaultValue = "7") int days) {
        return ApiResponse.success(adminConsoleService.analytics(Math.min(Math.max(days, 1), 90)));
    }

    @Operation(summary = "获取角色统计概览")
    @GetMapping("/api/v1/admin/roles")
    @PreAuthorize("hasAuthority('" + Permissions.SYSTEM_USER_READ + "')")
    ApiResponse<List<AdminConsoleSummaryDto.RoleSummary>> roles() {
        return ApiResponse.success(adminConsoleService.roles());
    }

    @Operation(summary = "重新计算用户存储用量")
    @PostMapping("/api/v1/admin/storage/recalculate")
    @PreAuthorize("hasAuthority('" + Permissions.SYSTEM_CONFIG_MANAGE + "')")
    ApiResponse<Integer> recalculateStorage() {
        UUID actorUserId = currentUserContext.requireCurrentUserId();
        // 存储重算会读取并改写全站用量账本：权限可能在签发 JWT 后被收回，
        // 必须按当前数据库状态复核管理员身份，并留下审计记录。
        adminActorGuard.requireFreshAdminActor(actorUserId);
        int updated = adminConsoleService.recalculateStorageUsage();
        adminAuditRecorder.recordWithMetadata(
                actorUserId, "ADMIN_STORAGE_RECALCULATE", "storage_usage", null,
                Map.of("updatedUsers", updated));
        return ApiResponse.success(updated);
    }
}
