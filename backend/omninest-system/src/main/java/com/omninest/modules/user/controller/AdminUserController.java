package com.omninest.modules.user.controller;

import com.omninest.common.api.ApiResponse;
import com.omninest.common.api.PageResponse;
import com.omninest.common.security.Permissions;
import com.omninest.modules.user.dto.AdminBatchUpdateUserStatusRequest;
import com.omninest.modules.user.dto.AdminBatchUserStatusResult;
import com.omninest.modules.user.dto.AdminOperationsDto;
import com.omninest.modules.user.dto.AdminCreateUserRequest;
import com.omninest.modules.user.dto.AdminUpdateUserStatusRequest;
import com.omninest.modules.user.dto.AuthUserDto;
import com.omninest.modules.user.service.AdminUserDeletionService;
import com.omninest.modules.user.service.AdminUserService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@Tag(name = "用户管理", description = "管理员对用户的增删改查操作")
@RestController
@RequiredArgsConstructor
public class AdminUserController {
    private final AdminUserService adminUserService;
    private final AdminUserDeletionService adminUserDeletionService;

    @Operation(summary = "分页查询用户列表", description = "支持按用户名、展示名、邮箱模糊搜索、角色编码精确过滤与白名单字段排序"
            + "（sort 取值 username/email/status/usedBytes/quotaBytes/createdAt，dir 取值 asc/desc）")
    @GetMapping("/api/v1/admin/users")
    @PreAuthorize("hasAuthority('" + Permissions.SYSTEM_USER_READ + "')")
    ApiResponse<PageResponse<AuthUserDto>> listUsers(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "50") int size,
            @RequestParam(defaultValue = "") String query,
            @RequestParam(defaultValue = "") String role,
            @RequestParam(defaultValue = "username") String sort,
            @RequestParam(defaultValue = "asc") String dir
    ) {
        var result = adminUserService.listUsers(page, size, query, role, sort, dir);
        return ApiResponse.success(PageResponse.of(
                result.getContent(), result.getNumber(), result.getSize(), result.getTotalElements()));
    }

    @Operation(summary = "创建新用户")
    @PostMapping("/api/v1/admin/users")
    @PreAuthorize("hasAuthority('" + Permissions.SYSTEM_USER_MANAGE + "')")
    ApiResponse<AuthUserDto> createUser(@Valid @RequestBody AdminCreateUserRequest request) {
        return ApiResponse.success(adminUserService.createUser(request));
    }

    @Operation(summary = "更新用户状态（启用/禁用）")
    @PatchMapping("/api/v1/admin/users/{userId}/status")
    @PreAuthorize("hasAuthority('" + Permissions.SYSTEM_USER_MANAGE + "')")
    ApiResponse<AuthUserDto> updateUserStatus(
            @PathVariable UUID userId,
            @Valid @RequestBody AdminUpdateUserStatusRequest request
    ) {
        return ApiResponse.success(adminUserService.updateUserStatus(userId, request.status()));
    }

    @Operation(summary = "批量更新用户状态（启用/禁用）", description = "逐项执行：不存在的用户、超级管理员与单行失败跳过并计入 failedIds，不中断其余项")
    @PatchMapping("/api/v1/admin/users/status/batch")
    @PreAuthorize("hasAuthority('" + Permissions.SYSTEM_USER_MANAGE + "')")
    ApiResponse<AdminBatchUserStatusResult> batchUpdateUserStatus(
            @Valid @RequestBody AdminBatchUpdateUserStatusRequest request
    ) {
        return ApiResponse.success(
                adminUserService.batchUpdateUserStatus(request.userIds(), request.status()));
    }

    @Operation(summary = "更新用户角色")
    @PatchMapping("/api/v1/admin/users/{userId}/roles")
    @PreAuthorize("hasAuthority('" + Permissions.SYSTEM_USER_MANAGE + "')")
    ApiResponse<AuthUserDto> updateUserRoles(
            @PathVariable UUID userId,
            @Valid @RequestBody AdminOperationsDto.UpdateUserRolesRequest request
    ) {
        return ApiResponse.success(adminUserService.updateUserRoles(userId, request.roles()));
    }

    /**
     * 物理删除空账户用户。
     *
     * <p>拒绝自我删除与超级管理员删除；用户仍持有业务内容或存储用量未清零时
     * 返回业务错误，仅空账户允许删除，详见
     * {@link AdminUserDeletionService#deleteUser}。</p>
     */
    @Operation(summary = "删除空账户用户", description = "拒绝自我删除与超级管理员；仍持有文件、照片等业务内容或存储用量未清零时返回业务错误")
    @DeleteMapping("/api/v1/admin/users/{userId}")
    @PreAuthorize("hasAuthority('" + Permissions.SYSTEM_USER_MANAGE + "')")
    ApiResponse<Void> deleteUser(@PathVariable UUID userId) {
        adminUserDeletionService.deleteUser(userId);
        return ApiResponse.success(null);
    }
}
