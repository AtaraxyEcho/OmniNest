package com.omninest.modules.file.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import java.util.UUID;

@Schema(description = "移动文件请求")
public record MoveFileNodeRequest(
        @Schema(description = "目标父文件夹 ID，null 表示移动到根目录") UUID parentId
) {
}
