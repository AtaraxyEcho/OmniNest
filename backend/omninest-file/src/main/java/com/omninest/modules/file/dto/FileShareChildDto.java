package com.omninest.modules.file.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import java.time.Instant;
import java.util.UUID;

/**
 * 分享文件夹的子项。
 *
 * <p>不返回规范化路径：分享访客只应看到目录名与层级标识，内部路径不属于分享承诺的范围。</p>
 *
 * @author OmniNest
 */
@Schema(description = "分享文件夹的子项")
public record FileShareChildDto(
        @Schema(description = "文件节点 ID") UUID id,
        @Schema(description = "父节点 ID，用于前端维护返回路径") UUID parentId,
        @Schema(description = "节点类型", example = "FILE", allowableValues = {"FILE", "FOLDER"}) String nodeType,
        @Schema(description = "文件名", example = "文档.pdf") String name,
        @Schema(description = "MIME 类型，文件夹为空") String mimeType,
        @Schema(description = "文件大小（字节），文件夹为汇总值") long sizeBytes,
        @Schema(description = "更新时间") Instant updatedAt,
        @Schema(description = "短期下载地址，文件夹为空") String downloadUrl
) {
}
