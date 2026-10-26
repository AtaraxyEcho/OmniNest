package com.omninest.modules.file.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

@Schema(description = "文件上传会话信息")
public record FileUploadSessionDto(
        @Schema(description = "会话 ID") UUID id,
        @Schema(description = "父文件夹 ID") UUID parentId,
        @Schema(description = "上传 ID", example = "upload-abc123") String uploadId,
        @Schema(description = "文件名", example = "文档.pdf") String fileName,
        @Schema(description = "文件大小（字节）", example = "1048576") long sizeBytes,
        @Schema(description = "分片大小（字节）", example = "5242880") int partSizeBytes,
        @Schema(description = "总分片数", example = "3") int totalParts,
        @Schema(description = "MIME 类型", example = "application/pdf") String mimeType,
        @Schema(description = "会话状态", example = "PENDING") String status,
        @Schema(description = "上传 URL") String uploadUrl,
        @Schema(description = "分片信息列表") List<FileUploadPartDto> parts,
        @Schema(description = "会话过期时间") Instant expiresAt
) {
}
