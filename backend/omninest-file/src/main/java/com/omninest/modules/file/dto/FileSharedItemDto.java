package com.omninest.modules.file.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import java.time.Instant;
import java.util.UUID;

@Schema(description = "分享文件项信息")
public record FileSharedItemDto(
        @Schema(description = "分享链接 ID") UUID shareId,
        @Schema(description = "文件节点信息") FileNodeDto file,
        @Schema(description = "文件所有者用户 ID") UUID ownerUserId,
        @Schema(description = "分享时间") Instant sharedAt,
        @Schema(description = "过期时间") Instant expiresAt
) {
}
