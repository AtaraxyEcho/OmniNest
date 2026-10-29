package com.omninest.modules.user.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.Size;
import java.util.List;
import java.util.UUID;

@Schema(description = "管理员批量更新用户状态请求")
public record AdminBatchUpdateUserStatusRequest(
        @Schema(description = "用户 ID 列表")
        @NotEmpty(message = "用户列表不能为空")
        @Size(max = 200, message = "单次最多更新 200 个用户") List<UUID> userIds,
        @Schema(description = "目标状态", example = "DISABLED", allowableValues = {"ACTIVE", "DISABLED"})
        @NotBlank(message = "用户状态不能为空") String status
) {
}
