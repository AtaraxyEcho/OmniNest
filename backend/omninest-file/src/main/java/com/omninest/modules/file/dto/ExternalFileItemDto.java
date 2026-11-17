package com.omninest.modules.file.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import java.time.Instant;

/**
 * 外部存储文件/目录信息。
 */
@Schema(description = "外部存储文件/目录信息")
public record ExternalFileItemDto(
        @Schema(description = "文件名", example = "photo.jpg") String name,
        @Schema(description = "远程路径", example = "/photos/photo.jpg") String path,
        @Schema(description = "是否为目录", example = "false") boolean isDir,
        @Schema(description = "文件大小（字节）", example = "1048576") long sizeBytes,
        @Schema(description = "修改时间") Instant modifiedAt,
        @Schema(description = "MIME 类型", example = "image/jpeg") String mimeType,
        @Schema(description = "文件哈希") String hash
) {
}
