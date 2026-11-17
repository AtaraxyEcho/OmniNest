package com.omninest.modules.file.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

@Schema(description = "重命名文件/文件夹请求")
public record RenameFileNodeRequest(
        @Schema(description = "新名称", example = "新文件名.pdf") @NotBlank @Size(max = 255) String name
) {
}
