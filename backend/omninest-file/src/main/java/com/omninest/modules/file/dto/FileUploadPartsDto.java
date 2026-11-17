package com.omninest.modules.file.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import java.util.List;
import java.util.UUID;

@Schema(description = "文件分片列表信息")
public record FileUploadPartsDto(
        @Schema(description = "会话 ID") UUID sessionId,
        @Schema(description = "上传 ID") String uploadId,
        @Schema(description = "总分片数", example = "3") int totalParts,
        @Schema(description = "已完成分片序号列表") List<Integer> completedPartNumbers,
        @Schema(description = "分片详情列表") List<FileUploadPartDto> parts
) {
}
