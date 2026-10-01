package com.omninest.modules.user.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import java.util.List;
import java.util.UUID;

@Schema(description = "批量更新用户状态结果")
public record AdminBatchUserStatusResult(
        @Schema(description = "成功更新的用户数量") int successCount,
        @Schema(description = "失败的用户 ID：不存在、超级管理员或单行更新失败") List<UUID> failedIds
) {
}
