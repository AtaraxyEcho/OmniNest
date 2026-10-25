package com.omninest.modules.file.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import java.time.Instant;

@Schema(description = "文件分片信息")
public record FileUploadPartDto(
        @Schema(description = "分片序号", example = "1") int partNumber,
        @Schema(description = "分片大小（字节）", example = "5242880") long sizeBytes,
        @Schema(description = "分片状态", example = "COMPLETED") String status,
        @Schema(description = "分片 ETag") String eTag,
        @Schema(description = "分片上传 URL") String uploadUrl,
        @Schema(description = "分片上传 URL 过期时间；无 URL 时为空") Instant uploadUrlExpiresAt
) {
}
