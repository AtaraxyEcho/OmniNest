package com.omninest.modules.file.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.Size;
import java.util.List;

/**
 * 批量下载地址签发请求。
 *
 * @param fileIds 文件节点 ID 列表
 * @author OmniNest
 */
@Schema(description = "批量下载地址签发请求")
public record BatchDownloadUrlRequest(
        @Schema(description = "文件节点 ID 列表") @NotEmpty @Size(max = 200) List<String> fileIds) {
}
