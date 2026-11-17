package com.omninest.modules.file.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.Size;

@Schema(description = "完成文件分片上传请求")
public record CompleteFileUploadPartRequest(
        @Schema(description = "分片序号", example = "1") @Min(value = 1, message = "分片序号必须大于 0") int partNumber,
        @Schema(description = "分片 ETag", example = "\"d41d8cd98f00b204e9800998ecf8427e\"") @Size(max = 160, message = "ETag 长度不能超过 160 个字符") String eTag
) {
}
