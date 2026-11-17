package com.omninest.modules.file.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import java.time.Instant;
import java.util.UUID;

/**
 * 文件版本条目。
 *
 * @param id 版本 ID
 * @param versionNo 版本序号（1 起，越大越新）
 * @param objectId 版本指向的文件对象 ID
 * @param changeType 变更类型（UPLOAD / EDIT / RESTORE / CURRENT）
 * @param sizeBytes 对象大小（字节）
 * @param createdBy 创建用户 ID
 * @param createdAt 创建时间
 * @param isCurrent 是否为文件当前对象
 * @param remark 版本备注
 * @author OmniNest
 */
@Schema(description = "文件版本条目")
public record FileVersionDto(
        @Schema(description = "版本 ID") UUID id,
        @Schema(description = "版本序号") int versionNo,
        @Schema(description = "文件对象 ID") UUID objectId,
        @Schema(description = "变更类型") String changeType,
        @Schema(description = "对象大小（字节）") long sizeBytes,
        @Schema(description = "创建用户 ID") UUID createdBy,
        @Schema(description = "创建时间") Instant createdAt,
        @Schema(description = "是否为当前对象") boolean isCurrent,
        @Schema(description = "版本备注") String remark
) {
}
