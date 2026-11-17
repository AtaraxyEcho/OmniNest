package com.omninest.modules.file.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotNull;
import java.util.UUID;

@Schema(description = "跨空间移动请求")
public record MoveToSpaceRequest(
        @Schema(description = "文件节点 ID") @NotNull(message = "文件节点 ID 不能为空") UUID fileNodeId
) {
}
