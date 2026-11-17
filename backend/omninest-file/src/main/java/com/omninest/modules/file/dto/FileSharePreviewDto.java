package com.omninest.modules.file.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import java.util.UUID;

/**
 * 分享链接预览信息。
 */
@Schema(description = "分享链接预览信息")
public record FileSharePreviewDto(
        @Schema(description = "分享链接 ID") UUID shareId,
        @Schema(description = "文件名", example = "文档.pdf") String fileName,
        @Schema(description = "MIME 类型", example = "application/pdf") String mimeType,
        @Schema(description = "文件大小（字节）", example = "1048576") long sizeBytes,
        @Schema(description = "资源类型", example = "FILE") String resourceType,
        @Schema(description = "是否需要密码", example = "false") boolean hasPassword,
        @Schema(description = "访客是否可以下载或转存文件") boolean allowDownloads,
        @Schema(description = "访客是否可获取原图") boolean originalQuality,
        @Schema(description = "访客可见内容是否包含位置信息") boolean includeLocation
) {
    /** 保留旧客户端与现有服务端调用方的构造签名。 */
    public FileSharePreviewDto(
            UUID shareId,
            String fileName,
            String mimeType,
            long sizeBytes,
            String resourceType,
            boolean hasPassword) {
        this(shareId, fileName, mimeType, sizeBytes, resourceType, hasPassword, true, true, true);
    }
}
