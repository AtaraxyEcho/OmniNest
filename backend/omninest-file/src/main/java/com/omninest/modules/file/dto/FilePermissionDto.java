package com.omninest.modules.file.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import java.util.UUID;

@Schema(description = "文件权限信息")
public record FilePermissionDto(
        @Schema(description = "文件 ID") UUID fileId,
        @Schema(description = "被授权用户 ID") UUID granteeUserId,
        @Schema(description = "被授权用户名", example = "user1") String granteeUsername,
        @Schema(description = "允许查看", example = "true") boolean allowView,
        @Schema(description = "允许下载", example = "true") boolean allowDownload,
        @Schema(description = "允许分享", example = "false") boolean allowShare,
        @Schema(description = "允许编辑", example = "false") boolean allowEdit
) {
}
