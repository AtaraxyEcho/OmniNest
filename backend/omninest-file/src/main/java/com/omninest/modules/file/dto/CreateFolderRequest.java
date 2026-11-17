package com.omninest.modules.file.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import java.util.UUID;

@Schema(description = "创建文件夹请求")
public record CreateFolderRequest(
        @Schema(description = "父文件夹 ID，null 表示创建在根目录") UUID parentId,
        @Schema(description = "文件夹名称", example = "我的文档") @NotBlank @Size(max = 255) String name
) {
}
