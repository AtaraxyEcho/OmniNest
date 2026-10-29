package com.omninest.modules.notification.controller;

import com.omninest.common.api.ApiResponse;
import com.omninest.common.audit.AdminAuditRecorder;
import com.omninest.common.security.CurrentUserContext;
import com.omninest.common.security.Permissions;
import com.omninest.modules.notification.dto.NotificationTypeDto;
import com.omninest.modules.notification.service.NotificationTypeService;
import com.omninest.common.security.FreshAdminActorVerifier;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.Size;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

/**
 * 通知类型配置接口控制器。
 *
 * @author OmniNest
 */
@RestController
@RequiredArgsConstructor
@Tag(name = "通知类型", description = "通知类型的查询与管理")
public class NotificationTypeController {

    private final NotificationTypeService notificationTypeService;
    private final CurrentUserContext currentUserContext;
    private final FreshAdminActorVerifier adminActorGuard;
    private final AdminAuditRecorder adminAuditRecorder;

    /**
     * 查询所有启用的通知类型（前端动态渲染设置项）。
     */
    @Operation(summary = "查询启用的通知类型", description = "查询所有启用的通知类型，用于前端动态渲染通知设置项")
    @GetMapping("/api/v1/notification-types")
    @PreAuthorize("hasAuthority('" + Permissions.ACTIVITY_READ + "')")
    ApiResponse<List<NotificationTypeDto>> listEnabled() {
        return ApiResponse.success(notificationTypeService.listEnabled());
    }

    /**
     * 查询全部通知类型（含禁用，管理员使用）。
     */
    @Operation(summary = "查询全部通知类型", description = "查询所有通知类型（含禁用），供管理员管理使用")
    @GetMapping("/api/v1/notification-types/all")
    @PreAuthorize("hasAuthority('" + Permissions.SYSTEM_CONFIG_READ + "')")
    ApiResponse<List<NotificationTypeDto>> listAll() {
        return ApiResponse.success(notificationTypeService.listAll());
    }

    /**
     * 更新通知类型配置。
     */
    @Operation(summary = "更新通知类型", description = "更新指定通知类型的配置信息，包括标签、图标、颜色、排序和启用状态")
    @PutMapping("/api/v1/notification-types/{id}")
    @PreAuthorize("hasAuthority('" + Permissions.SYSTEM_CONFIG_MANAGE + "')")
    ApiResponse<NotificationTypeDto> update(
            @PathVariable UUID id,
            @RequestBody @Valid UpdateTypeRequest request
    ) {
        UUID actorUserId = currentUserContext.requireCurrentUserId();
        adminActorGuard.requireFreshAdminActor(actorUserId);
        NotificationTypeDto result = notificationTypeService.update(
                id,
                request.label(),
                request.description(),
                request.icon(),
                request.color(),
                request.sortOrder(),
                request.enabled()
        );
        // 请求体各字段都是"传了才改"的可选语义，Map.of 不接受 null：
        // 省略 enabled 时原来连变更本身都会被 NPE 打成一个已经生效却返回 500 的请求。
        adminAuditRecorder.recordWithMetadata(
                actorUserId,
                "ADMIN_NOTIFICATION_TYPE_UPDATE",
                "notification_types",
                id,
                changedFields(request)
        );
        return ApiResponse.success(result);
    }

    /**
     * 收集本次实际提交的字段，供审计载荷记录改了什么。
     */
    private static Map<String, Object> changedFields(UpdateTypeRequest request) {
        Map<String, Object> changed = new LinkedHashMap<>();
        if (request.label() != null) {
            changed.put("label", request.label());
        }
        if (request.description() != null) {
            changed.put("description", request.description());
        }
        if (request.icon() != null) {
            changed.put("icon", request.icon());
        }
        if (request.color() != null) {
            changed.put("color", request.color());
        }
        if (request.sortOrder() != null) {
            changed.put("sortOrder", request.sortOrder());
        }
        if (request.enabled() != null) {
            changed.put("enabled", request.enabled());
        }
        return changed;
    }

    /**
     * 更新类型请求体。
     */
    public record UpdateTypeRequest(
            @Size(min = 1, max = 64)
            String label,
            @Size(max = 500)
            String description,
            @Size(max = 64)
            String icon,
            @Size(max = 32)
            String color,
            @Min(0)
            Integer sortOrder,
            Boolean enabled
    ) {
    }
}
