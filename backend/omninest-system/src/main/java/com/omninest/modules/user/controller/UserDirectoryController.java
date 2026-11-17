package com.omninest.modules.user.controller;

import com.omninest.common.api.ApiResponse;
import com.omninest.common.api.PageResponse;
import com.omninest.common.security.CurrentUserContext;
import com.omninest.common.security.Permissions;
import com.omninest.modules.user.dto.UserDirectoryDtos.UserDirectoryEntry;
import com.omninest.modules.user.service.UserDirectoryQueryService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.constraints.Size;
import lombok.RequiredArgsConstructor;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** 分享收件人选择所需的最小活动用户目录。 */
@Validated
@RestController
@RequiredArgsConstructor
@RequestMapping("/api/v1/users")
@Tag(name = "用户目录", description = "分享收件人选择")
public class UserDirectoryController {

    private final UserDirectoryQueryService userDirectoryQueryService;
    private final CurrentUserContext currentUserContext;

    @Operation(summary = "搜索分享收件人", description = "返回活动用户的最小标识字段，不含邮箱或权限信息")
    @GetMapping("/directory")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_WRITE + "')")
    public ApiResponse<PageResponse<UserDirectoryEntry>> searchShareRecipients(
            @RequestParam(required = false) @Size(max = 100) String query,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "10") int size) {
        currentUserContext.requireCurrentUserId();
        return ApiResponse.success(userDirectoryQueryService.findActiveUsers(query, page, size));
    }
}
