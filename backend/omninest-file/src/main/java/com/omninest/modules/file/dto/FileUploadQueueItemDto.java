package com.omninest.modules.file.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import java.time.Instant;
import java.util.UUID;

@Schema(description = "文件上传队列项")
public record FileUploadQueueItemDto(
        @Schema(description = "会话 ID") UUID id,
        @Schema(description = "上传 ID") String uploadId,
        @Schema(description = "父文件夹 ID") UUID parentId,
        @Schema(description = "文件名", example = "文档.pdf") String fileName,
        @Schema(description = "文件大小（字节）", example = "1048576") long sizeBytes,
        @Schema(description = "分片大小（字节）", example = "5242880") int partSizeBytes,
        @Schema(description = "总分片数", example = "3") int totalParts,
        @Schema(description = "已上传分片数", example = "2") int uploadedParts,
        @Schema(description = "会话状态", example = "UPLOADING") String status,
        @Schema(description = "空间类型", example = "SHARED") String spaceType,
        @Schema(description = "会话过期时间") Instant expiresAt,
        @Schema(description = "更新时间") Instant updatedAt
) {
}
