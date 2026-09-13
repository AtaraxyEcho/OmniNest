package com.omninest.modules.file.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotNull;
import java.util.UUID;

/**
 * 保存文件新版本请求。
 *
 * @param objectId 已上传的新文件对象 ID
 * @param sizeBytes 新对象大小（字节）
 * @param remark 版本备注
 * @author OmniNest
 */
@Schema(description = "保存文件新版本请求")
public record SaveFileVersionRequest(
        @Schema(description = "新文件对象 ID") @NotNull UUID objectId,
        @Schema(description = "新对象大小（字节）") long sizeBytes,
        @Schema(description = "版本备注") String remark
) {
}
