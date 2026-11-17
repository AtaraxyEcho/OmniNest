package com.omninest.modules.reader.dto;

import io.swagger.v3.oas.annotations.media.Schema;

import java.time.Instant;
import java.util.UUID;

/**
 * 阅读源文件的临时下载票据。
 *
 * @param itemId 阅读条目标识
 * @param fileName 下载文件名
 * @param downloadUrl 临时下载地址
 * @param sizeBytes 文件大小
 * @param sha256 文件摘要
 * @param expiresAt 票据过期时间
 * @author OmniNest
 */
@Schema(description = "阅读源文件临时下载票据")
public record ReaderFileTicketDto(
        @Schema(description = "阅读条目 ID") UUID itemId,
        @Schema(description = "下载文件名") String fileName,
        @Schema(description = "临时下载地址") String downloadUrl,
        @Schema(description = "文件大小") long sizeBytes,
        @Schema(description = "SHA-256 摘要") String sha256,
        @Schema(description = "票据过期时间") Instant expiresAt
) {
}
