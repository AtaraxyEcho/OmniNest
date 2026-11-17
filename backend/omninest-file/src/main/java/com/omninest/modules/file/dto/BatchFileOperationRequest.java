package com.omninest.modules.file.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.Size;
import java.util.List;
import java.util.UUID;

/**
 * 批量文件操作请求（删除/恢复/彻底删除/收藏）
 */
@Schema(description = "批量文件操作请求")
public record BatchFileOperationRequest(
        @Schema(description = "文件 ID 列表") @NotEmpty @Size(max = 200) List<UUID> fileIds
) {
}
