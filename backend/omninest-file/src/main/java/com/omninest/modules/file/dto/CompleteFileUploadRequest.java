package com.omninest.modules.file.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Size;
import java.util.List;
import java.util.UUID;

@Schema(description = "完成文件上传请求")
public record CompleteFileUploadRequest(
        @Schema(description = "文件 SHA-256 哈希值") @Size(min = 64, max = 64, message = "SHA-256 必须为 64 位十六进制字符串") String sha256,
        @Schema(description = "分片完成信息列表") @Valid List<CompleteFileUploadPartRequest> parts,
        @Schema(description = "作为目标文件的新版本保存（不新建文件节点）") UUID asVersionOfFileId
) {
}
