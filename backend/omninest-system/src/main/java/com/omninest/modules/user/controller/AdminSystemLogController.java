package com.omninest.modules.user.controller;

import com.omninest.common.api.ApiResponse;
import com.omninest.common.security.Permissions;
import com.omninest.modules.user.dto.AdminSystemLogPageDto;
import com.omninest.modules.user.service.AdminSystemLogService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * 管理端系统运行日志接口。
 */
@Tag(name = "运维管理", description = "系统运维操作与监控")
@RestController
@RequiredArgsConstructor
public class AdminSystemLogController {
    private final AdminSystemLogService adminSystemLogService;

    @Operation(summary = "分页查询当前 API 进程的运行日志")
    @GetMapping("/api/v1/admin/logs/system/page")
    @PreAuthorize("hasAuthority('" + Permissions.SYSTEM_CONFIG_READ + "')")
    ApiResponse<AdminSystemLogPageDto> page(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "25") int size,
            @RequestParam(defaultValue = "") String level,
            @RequestParam(defaultValue = "") String source,
            @RequestParam(defaultValue = "") String query
    ) {
        return ApiResponse.success(adminSystemLogService.page(page, size, level, source, query));
    }
}
