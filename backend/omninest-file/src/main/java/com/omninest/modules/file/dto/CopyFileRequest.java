package com.omninest.modules.file.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import java.util.UUID;

/**
 * 文件复制请求体。
 *
 * @param targetParentId 目标父文件夹 ID，null 表示复制到根目录
 */
@Schema(description = "文件复制请求")
public record CopyFileRequest(
        @Schema(description = "目标父文件夹 ID，null 表示复制到根目录") UUID targetParentId
) {
}
