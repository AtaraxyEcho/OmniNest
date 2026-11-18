package com.omninest.modules.user.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.Size;
import java.util.Set;

@Schema(description = "管理员创建用户请求")
public record AdminCreateUserRequest(
        @Schema(description = "用户名", example = "newuser") @NotBlank(message = "用户名不能为空") @Size(max = 80, message = "用户名长度不能超过 80 个字符") String username,
        @Schema(description = "展示名称", example = "新用户") @Size(max = 120, message = "展示名称长度不能超过 120 个字符") String displayName,
        @Schema(description = "邮箱", example = "user@example.com") @Email(message = "邮箱格式不正确") @Size(max = 255, message = "邮箱长度不能超过 255 个字符") String email,
        @Schema(description = "密码", example = "password123") @NotBlank(message = "密码不能为空") @Size(min = 8, max = 64, message = "密码长度必须在 8 到 64 个字符之间") String password,
        @Schema(description = "角色集合") Set<String> roles,
        @Schema(description = "账户状态", example = "ACTIVE") String status,
        @Schema(description = "可选存储配额（字节）；未提供时使用系统默认值", example = "53687091200")
        @Min(value = 1_073_741_824L, message = "存储配额不得低于 1 GiB")
        @Max(value = 10_737_418_240_000L, message = "存储配额不得高于 10000 GiB")
        Long quotaBytes,
        @Schema(description = "是否要求用户首次登录后修改密码") Boolean requirePasswordChange
) {
    /** 保留原创建请求构造器，兼容既有 Java 调用方。 */
    public AdminCreateUserRequest(
            String username,
            String displayName,
            String email,
            String password,
            Set<String> roles,
            String status
    ) {
        this(username, displayName, email, password, roles, status, null, null);
    }

    /** 保留配额参数版本，兼容既有 Java 调用方。 */
    public AdminCreateUserRequest(
            String username,
            String displayName,
            String email,
            String password,
            Set<String> roles,
            String status,
            Long quotaBytes
    ) {
        this(username, displayName, email, password, roles, status, quotaBytes, null);
    }
}
