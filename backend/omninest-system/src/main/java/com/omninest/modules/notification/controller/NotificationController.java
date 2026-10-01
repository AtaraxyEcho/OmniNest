package com.omninest.modules.notification.controller;

import com.omninest.common.api.ApiResponse;
import com.omninest.common.api.PageResponse;
import com.omninest.common.security.CurrentUserContext;
import com.omninest.common.security.Permissions;
import com.omninest.modules.notification.dto.NotificationDto;
import com.omninest.modules.notification.service.NotificationService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * 站内通知接口控制器。
 */
@RestController
@RequiredArgsConstructor
@Tag(name = "通知", description = "用户通知的查询与管理")
public class NotificationController {

    private final CurrentUserContext currentUserContext;
    private final NotificationService notificationService;

    @Operation(summary = "分页查询通知列表", description = "分页查询当前用户的站内通知列表，unreadOnly=true 时仅返回未读")
    @GetMapping("/api/v1/notifications")
    @PreAuthorize(
            "hasAuthority('" + Permissions.ACTIVITY_READ + "') or hasAuthority('" + Permissions.PROFILE_READ + "')"
    )
    ApiResponse<PageResponse<NotificationDto>> list(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size,
            @RequestParam(defaultValue = "false") boolean unreadOnly
    ) {
        UUID userId = currentUserContext.requireCurrentUserId();
        List<NotificationDto> items = notificationService.list(userId, page, size, unreadOnly);
        long total = notificationService.totalCount(userId, unreadOnly);
        return ApiResponse.success(PageResponse.of(items, page, size, total));
    }

    @Operation(summary = "查询未读通知数", description = "获取当前用户的未读通知数量")
    @GetMapping("/api/v1/notifications/unread-count")
    @PreAuthorize(
            "hasAuthority('" + Permissions.ACTIVITY_READ + "') or hasAuthority('" + Permissions.PROFILE_READ + "')"
    )
    ApiResponse<Long> unreadCount() {
        UUID userId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(notificationService.unreadCount(userId));
    }

    @Operation(summary = "标记通知已读", description = "批量标记指定通知为已读状态")
    @PutMapping("/api/v1/notifications/read")
    @PreAuthorize("hasAuthority('" + Permissions.ACTIVITY_WRITE + "')")
    ApiResponse<Void> markRead(@RequestBody Map<String, List<UUID>> body) {
        UUID userId = currentUserContext.requireCurrentUserId();
        List<UUID> ids = body.get("ids");
        if (ids == null || ids.isEmpty()) {
            return ApiResponse.success(null);
        }
        notificationService.markRead(userId, ids);
        return ApiResponse.success(null);
    }

    @Operation(summary = "标记全部已读", description = "将当前用户的所有未读通知标记为已读")
    @PutMapping("/api/v1/notifications/read-all")
    @PreAuthorize("hasAuthority('" + Permissions.ACTIVITY_WRITE + "')")
    ApiResponse<Void> markAllRead() {
        UUID userId = currentUserContext.requireCurrentUserId();
        notificationService.markAllRead(userId);
        return ApiResponse.success(null);
    }

    @Operation(summary = "删除通知", description = "删除当前用户的指定通知")
    @DeleteMapping("/api/v1/notifications/{notificationId}")
    @PreAuthorize("hasAuthority('" + Permissions.ACTIVITY_WRITE + "')")
    ApiResponse<Void> delete(@PathVariable UUID notificationId) {
        UUID userId = currentUserContext.requireCurrentUserId();
        notificationService.delete(userId, notificationId);
        return ApiResponse.success(null);
    }

    @Operation(summary = "清空通知", description = "清空当前用户的全部站内通知")
    @DeleteMapping("/api/v1/notifications")
    @PreAuthorize("hasAuthority('" + Permissions.ACTIVITY_WRITE + "')")
    ApiResponse<Void> clearAll() {
        UUID userId = currentUserContext.requireCurrentUserId();
        notificationService.clearAll(userId);
        return ApiResponse.success(null);
    }
}
