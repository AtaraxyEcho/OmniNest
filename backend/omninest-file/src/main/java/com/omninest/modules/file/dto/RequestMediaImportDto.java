package com.omninest.modules.file.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import java.util.List;
import java.util.UUID;

/**
 * 从文件库选择媒体并重新投递自动导入任务。
 *
 * @param fileNodeIds 文件或目录节点 ID
 * @param mediaType 目标媒体类型
 */
@Schema(description = "从文件库选择媒体并重新投递自动导入任务")
public record RequestMediaImportDto(
        @Schema(description = "个人文件或目录节点 ID，单次最多 100 个")
        @NotEmpty @Size(max = 100) List<@NotNull UUID> fileNodeIds,
        @Schema(description = "媒体类型：VIDEO、PHOTO 或 MUSIC")
        @NotNull @Pattern(regexp = "VIDEO|PHOTO|MUSIC") String mediaType
) {
}
