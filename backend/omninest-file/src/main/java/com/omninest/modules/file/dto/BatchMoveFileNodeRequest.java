package com.omninest.modules.file.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.Size;
import java.util.List;
import java.util.UUID;

/**
 * 批量移动文件请求
 */
@Schema(description = "批量移动文件请求")
public record BatchMoveFileNodeRequest(
        @Schema(description = "文件 ID 列表") @NotEmpty @Size(max = 200) List<UUID> fileIds,
        @Schema(description = "目标父文件夹 ID，null 表示移动到根目录") UUID parentId
) {
}
