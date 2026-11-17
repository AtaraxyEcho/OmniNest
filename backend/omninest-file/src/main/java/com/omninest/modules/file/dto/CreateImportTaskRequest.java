package com.omninest.modules.file.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotBlank;
import java.util.UUID;

/**
 * 创建外部存储导入任务请求。
 *
 * @author OmniNest
 */
@Schema(description = "创建外部存储导入任务请求")
public record CreateImportTaskRequest(
        @Schema(description = "源路径", example = "/photos/vacation") @NotBlank(message = "源路径不能为空") String sourcePath,
        @Schema(description = "目标文件夹 ID，null 表示导入到根目录") UUID targetParentId,
        @Schema(description = "空间类型：PERSONAL 或 SHARED，默认 PERSONAL") String spaceType,
        @Schema(description = "导入源类型：FILE 或 DIRECTORY，默认 FILE", example = "DIRECTORY") String sourceKind
) {
}
