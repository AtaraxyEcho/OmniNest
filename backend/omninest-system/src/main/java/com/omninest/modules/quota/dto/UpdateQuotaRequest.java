package com.omninest.modules.quota.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.Min;

/**
 * 管理员修改用户存储配额请求。
 */
@Schema(description = "管理员修改用户存储配额请求")
public record UpdateQuotaRequest(
        @Schema(description = "存储配额（字节）", example = "10737418240") @Min(0) long quotaBytes
) {
}
