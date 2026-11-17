package com.omninest.modules.file.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import java.util.UUID;

@Schema(description = "创建文件上传会话请求")
public record CreateFileUploadSessionRequest(
        @Schema(description = "父文件夹 ID，null 表示上传到根目录") UUID parentId,
        @Schema(description = "文件名", example = "文档.pdf") @NotBlank(message = "文件名不能为空") @Size(max = 255, message = "文件名长度不能超过 255 个字符") String fileName,
        @Schema(description = "文件大小（字节）", example = "1048576") @Min(value = 1, message = "文件大小必须大于 0") long sizeBytes,
        @Schema(description = "MIME 类型", example = "application/pdf") @Size(max = 160, message = "MIME 类型长度不能超过 160 个字符") String mimeType,
        @Schema(description = "文件 SHA-256 哈希值") @Size(min = 64, max = 64, message = "SHA-256 必须为 64 位十六进制字符串") String sha256,
        @Schema(description = "分片大小（字节）", example = "5242880") @Min(value = 1, message = "分片大小必须大于 0") Integer partSizeBytes,
        @Schema(description = "目标空间类型：PERSONAL / SHARED，默认 PERSONAL") String spaceType,
        @Schema(description = "作为目标文件的新版本上传（跳过同名冲突检查）") UUID asVersionOfFileId
) {
}
