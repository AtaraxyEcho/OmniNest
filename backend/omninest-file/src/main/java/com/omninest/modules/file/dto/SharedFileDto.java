package com.omninest.modules.file.dto;

import com.omninest.modules.file.domain.FilePermission;
import io.swagger.v3.oas.annotations.media.Schema;
import java.time.Instant;
import java.util.UUID;

@Schema(description = "已分享文件信息")
public record SharedFileDto(
        @Schema(description = "文件节点信息") FileNodeDto file,
        @Schema(description = "文件所有者用户 ID") UUID ownerUserId,
        @Schema(description = "文件所有者用户名", example = "admin") String ownerUsername,
        @Schema(description = "分享权限") FilePermission permission,
        @Schema(description = "分享时间") Instant sharedAt
) {
}
