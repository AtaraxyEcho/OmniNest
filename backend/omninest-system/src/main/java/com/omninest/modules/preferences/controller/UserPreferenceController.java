package com.omninest.modules.preferences.controller;

import com.omninest.common.api.ApiResponse;
import com.omninest.common.security.CurrentUserContext;
import com.omninest.common.security.Permissions;
import com.omninest.modules.preferences.dto.UserPreferenceDtos.UserPreferenceDto;
import com.omninest.modules.preferences.dto.UserPreferenceDtos.UserPreferencePatchRequest;
import com.omninest.modules.preferences.service.UserPreferenceService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * 用户偏好设置控制器，支持按作用域读取和更新。
 *
 * @author Notask Flow Team
 */
@RestController
@RequiredArgsConstructor
@Tag(name = "用户偏好", description = "用户偏好设置的查询与修改")
public class UserPreferenceController {
    private final CurrentUserContext currentUserContext;
    private final UserPreferenceService userPreferenceService;

    @Operation(summary = "查询用户偏好", description = "根据作用域查询当前用户的偏好设置")
    @GetMapping("/api/v1/preferences/{scope}")
    @PreAuthorize("hasAuthority('" + Permissions.PREFERENCE_READ + "')")
    ApiResponse<UserPreferenceDto> get(@PathVariable String scope) {
        return ApiResponse.success(userPreferenceService.get(currentUserContext.requireCurrentUserId(), scope));
    }

    @Operation(summary = "增量更新用户偏好", description = "按版本增量更新当前用户指定作用域的顶层偏好")
    @PatchMapping("/api/v1/preferences/{scope}")
    @PreAuthorize("hasAuthority('" + Permissions.PREFERENCE_WRITE + "')")
    ApiResponse<UserPreferenceDto> patch(
            @PathVariable String scope,
            @Valid @RequestBody UserPreferencePatchRequest request
    ) {
        return ApiResponse.success(userPreferenceService.patch(currentUserContext.requireCurrentUserId(), scope, request));
    }

    @Operation(summary = "删除用户偏好", description = "按版本删除当前用户指定作用域的偏好")
    @DeleteMapping("/api/v1/preferences/{scope}")
    @PreAuthorize("hasAuthority('" + Permissions.PREFERENCE_WRITE + "')")
    ApiResponse<Void> delete(
            @PathVariable String scope,
            @RequestParam Long baseVersion
    ) {
        userPreferenceService.delete(currentUserContext.requireCurrentUserId(), scope, baseVersion);
        return ApiResponse.success(null);
    }
}
