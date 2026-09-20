package com.omninest.modules.user.controller;

import com.omninest.common.api.ApiResponse;
import com.omninest.common.security.CurrentUserContext;
import com.omninest.common.security.Permissions;
import com.omninest.modules.user.domain.AuthActiveSession;
import com.omninest.modules.user.dto.AuthUserDto;
import com.omninest.modules.user.service.CurrentUserService;
import java.util.List;
import com.omninest.modules.user.dto.ChangePasswordRequest;
import com.omninest.modules.user.service.WebShareBaseUrlService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
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
import org.springframework.web.multipart.MultipartFile;

/**
 * 当前用户资料与会话接口。
 *
 * @author OmniNest
 */
@RestController
@RequiredArgsConstructor
@Tag(name = "当前用户", description = "当前登录用户的个人信息与操作")
public class MeController {
    private final CurrentUserService currentUserService;
    private final CurrentUserContext currentUserContext;
    private final WebShareBaseUrlService webShareBaseUrlService;

    @Operation(summary = "获取当前用户信息", description = "返回当前登录用户的基本信息")
    @GetMapping("/api/v1/me")
    @PreAuthorize("hasAuthority('" + Permissions.PROFILE_READ + "')")
    ApiResponse<AuthUserDto> me() {
        return ApiResponse.success(currentUserService.currentUser());
    }

    /**
     * 获取分享链接基址。
     *
     * <p>返回部署者配置的对外 Web 地址；未配置时 data 为空，客户端按
     * 平台语义回退（Web 用当前 origin，原生端退化为 API origin 并提示）。</p>
     */
    @Operation(summary = "获取分享链接基址", description = "返回服务器配置的对外 Web 地址，未配置时为空")
    @GetMapping("/api/v1/me/web-share-base-url")
    @PreAuthorize("hasAuthority('" + Permissions.PROFILE_READ + "')")
    ApiResponse<String> webShareBaseUrl() {
        return ApiResponse.success(webShareBaseUrlService.resolveShareBaseUrl());
    }

    @PutMapping("/api/v1/me/password")
    @PreAuthorize("hasAuthority('" + Permissions.PROFILE_WRITE + "')")
    ApiResponse<Void> changePassword(@Valid @RequestBody ChangePasswordRequest request) {
        UUID userId = currentUserContext.requireCurrentUserId();
        currentUserService.changePassword(userId, request.oldPassword(), request.newPassword());
        return ApiResponse.success(null);
    }

    @PutMapping("/api/v1/me/avatar")
    @PreAuthorize("hasAuthority('" + Permissions.PROFILE_WRITE + "')")
    ApiResponse<String> uploadAvatar(@RequestParam("file") MultipartFile file) {
        UUID userId = currentUserContext.requireCurrentUserId();
        String avatarUrl = currentUserService.uploadAvatar(userId, file);
        return ApiResponse.success(avatarUrl);
    }

    /**
     * 查询当前用户的活跃会话列表。
     */
    @GetMapping("/api/v1/me/sessions")
    @PreAuthorize("hasAuthority('" + Permissions.PROFILE_READ + "')")
    ApiResponse<List<AuthActiveSession>> sessions() {
        UUID userId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(currentUserService.activeSessions(userId));
    }

    /**
     * 撤销指定会话（主动登出其他设备）。
     * Redis 先写保证即时生效，DB 后写保证持久化。
     */
    @DeleteMapping("/api/v1/me/sessions/{sessionId}")
    @PreAuthorize("hasAuthority('" + Permissions.PROFILE_WRITE + "')")
    ApiResponse<Void> revokeSession(@PathVariable UUID sessionId) {
        UUID userId = currentUserContext.requireCurrentUserId();
        currentUserService.revokeSession(userId, sessionId);
        return ApiResponse.success(null);
    }
}
