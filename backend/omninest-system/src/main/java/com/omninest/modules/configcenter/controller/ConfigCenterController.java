package com.omninest.modules.configcenter.controller;

import com.omninest.common.api.ApiResponse;
import com.omninest.common.audit.AdminAuditRecorder;
import com.omninest.common.security.CurrentUserContext;
import com.omninest.common.security.Permissions;
import com.omninest.modules.configcenter.domain.ConfigSurface;
import com.omninest.modules.configcenter.dto.ConfigEntryDto;
import com.omninest.modules.configcenter.dto.ConfigHistoryDto;
import com.omninest.modules.configcenter.service.ConfigCenterService;
import com.omninest.common.security.FreshAdminActorVerifier;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequiredArgsConstructor
@Tag(name = "配置中心", description = "系统配置项的查询与管理")
public class ConfigCenterController {
    private final ConfigCenterService configCenterService;
    private final CurrentUserContext currentUserContext;
    private final FreshAdminActorVerifier adminActorGuard;
    private final AdminAuditRecorder adminAuditRecorder;

    @Operation(summary = "查询所有配置项", description = "获取系统配置中心的所有配置项列表")
    @GetMapping("/api/v1/admin/configs")
    @PreAuthorize("hasAuthority('" + Permissions.SYSTEM_CONFIG_READ + "')")
    ApiResponse<List<ConfigEntryDto>> list(@RequestParam(required = false) ConfigSurface surface) {
        return ApiResponse.success(configCenterService.list(surface));
    }

    @Operation(summary = "更新配置项", description = "更新指定配置键的值，媒体运行开关类配置仅允许超级管理员修改")
    @PutMapping("/api/v1/admin/configs/{key}")
    @PreAuthorize("hasAuthority('" + Permissions.SYSTEM_CONFIG_MANAGE + "')")
    ApiResponse<ConfigEntryDto> update(
            @PathVariable String key,
            @Valid @RequestBody UpdateConfigRequest body
    ) {
        UUID actorUserId = currentUserContext.requireCurrentUserId();
        adminActorGuard.requireFreshAdminActor(actorUserId);
        ConfigEntryDto result = configCenterService.update(key, body.value(), body.reason(), actorUserId);
        adminAuditRecorder.recordWithMetadata(
                actorUserId,
                "ADMIN_CONFIG_UPDATE",
                "sys_config_entries",
                null,
                Map.of("key", key, "reason", body.reason() == null ? "" : body.reason())
        );
        return ApiResponse.success(result);
    }

    /**
     * 查询指定配置键的变更历史。
     *
     * @param key 配置键
     * @return 历史记录列表
     */
    @Operation(summary = "查询配置变更历史", description = "查询指定配置键的历史变更记录列表")
    @GetMapping("/api/v1/admin/configs/{key}/history")
    @PreAuthorize("hasAuthority('" + Permissions.SYSTEM_CONFIG_READ + "')")
    ApiResponse<List<ConfigHistoryDto>> listHistory(@PathVariable String key) {
        return ApiResponse.success(configCenterService.listHistory(key));
    }

    /**
     * 根据历史记录回滚配置值。
     * @param historyId 历史记录 ID
     * @return 回滚后的配置 DTO
     */
    @Operation(summary = "回滚配置值", description = "根据历史记录将配置值回滚到指定版本，媒体运行开关类配置仅允许超级管理员回滚")
    @PostMapping("/api/v1/admin/configs/history/{historyId}/rollback")
    @PreAuthorize("hasAuthority('" + Permissions.SYSTEM_CONFIG_MANAGE + "')")
    ApiResponse<ConfigEntryDto> rollback(@PathVariable UUID historyId) {
        UUID actorUserId = currentUserContext.requireCurrentUserId();
        adminActorGuard.requireFreshAdminActor(actorUserId);
        ConfigEntryDto result = configCenterService.rollback(historyId, actorUserId);
        adminAuditRecorder.recordWithMetadata(
                actorUserId,
                "ADMIN_CONFIG_ROLLBACK",
                "sys_config_history",
                historyId,
                Map.of()
        );
        return ApiResponse.success(result);
    }

    public record UpdateConfigRequest(
            @NotNull @Size(max = 8192) String value,
            @Size(max = 500) String reason
    ) {
    }
}
