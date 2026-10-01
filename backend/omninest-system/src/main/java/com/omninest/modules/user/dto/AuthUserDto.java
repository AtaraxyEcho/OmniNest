package com.omninest.modules.user.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import java.time.Instant;
import java.util.Set;
import java.util.UUID;

@Schema(description = "当前登录用户信息")
public record AuthUserDto(
        @Schema(description = "用户 ID", example = "550e8400-e29b-41d4-a716-446655440000") UUID id,
        @Schema(description = "用户名", example = "admin") String username,
        @Schema(description = "展示名称", example = "管理员") String displayName,
        @Schema(description = "头像 URL") String avatarUrl,
        @Schema(description = "邮箱", example = "admin@example.com") String email,
        @Schema(description = "账户状态", example = "ACTIVE") String status,
        @Schema(description = "主要角色", example = "SUPER_ADMIN") String role,
        @Schema(description = "角色集合") Set<String> roles,
        @Schema(description = "权限集合") Set<String> permissions,
        @Schema(description = "存储配额（字节）", example = "10737418240") long quotaBytes,
        @Schema(description = "已用存储（字节）", example = "1073741824") long usedBytes,
        @Schema(description = "创建时间") Instant createdAt,
        @Schema(description = "是否已确认启用两步验证；仅管理用户列表填充，其余场景为空") Boolean twoFactorEnabled
) {
}
