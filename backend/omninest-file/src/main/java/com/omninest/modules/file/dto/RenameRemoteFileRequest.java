package com.omninest.modules.file.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotBlank;

/**
 * 远程文件重命名请求。
 */
@Schema(description = "远程文件重命名请求")
public record RenameRemoteFileRequest(
        @Schema(description = "原路径", example = "/photos/old.jpg") @NotBlank(message = "原路径不能为空") String oldPath,
        @Schema(description = "新名称", example = "new.jpg") @NotBlank(message = "新名称不能为空") String newName
) {
}
