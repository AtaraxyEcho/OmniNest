package com.omninest.modules.quota.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.Size;
import java.util.List;
import java.util.UUID;

/**
 * 管理员批量修改用户存储配额请求。
 */
@Schema(description = "管理员批量修改用户存储配额请求")
public record BatchUpdateQuotaRequest(
        @Schema(description = "用户 ID 列表")
        @NotEmpty
        @Size(max = 200, message = "单次最多更新 200 个用户") List<UUID> userIds,
        @Schema(description = "存储配额（字节）", example = "10737418240") @Min(0) long quotaBytes
) {
}
