package com.omninest.modules.file.dto;

import io.swagger.v3.oas.annotations.media.Schema;

@Schema(description = "文件上传策略配置")
public record FileUploadPolicyDto(
        @Schema(description = "直传最大文件大小（字节）", example = "10485760") long directUploadMaxBytes,
        @Schema(description = "默认分片大小（字节）", example = "5242880") int defaultPartSizeBytes,
        @Schema(description = "最大分片大小（字节）", example = "104857600") int maxPartSizeBytes,
        @Schema(description = "最大分片数", example = "10000") int maxTotalParts,
        @Schema(description = "最大并发分片数", example = "4") int maxConcurrentParts,
        @Schema(description = "单文件有效上限（字节）", example = "104857600000") long maxFileSizeBytes,
        @Schema(description = "上传 URL 有效期（秒）", example = "3600") long uploadUrlTtlSeconds,
        @Schema(description = "每秒最大分片请求数", example = "10") int maxPartsPerSecond,
        @Schema(description = "是否启用带宽限制", example = "false") boolean bandwidthLimitEnabled
) {
}
