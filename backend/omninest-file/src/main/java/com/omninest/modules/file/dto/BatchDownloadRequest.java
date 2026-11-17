package com.omninest.modules.file.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.Size;
import java.util.List;

/**
 * 批量文件下载请求（打包为 ZIP）
 */
@Schema(description = "批量文件下载请求")
public record BatchDownloadRequest(
        @Schema(description = "文件 ID 列表") @NotEmpty @Size(max = 200) List<String> fileIds
) {
}
