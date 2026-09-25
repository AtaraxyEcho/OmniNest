package com.omninest.modules.file.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import java.util.UUID;

/**
 * 批量文件操作的单项结果。
 *
 * @param id 文件节点 ID
 * @param status 处理结果：SUCCESS / FAILED / SKIPPED
 * @param errorCode 失败时的稳定错误码
 * @param message 可读说明
 * @author OmniNest
 */
@Schema(description = "批量文件操作单项结果")
public record BatchItemResult(
        @Schema(description = "文件节点 ID") UUID id,
        @Schema(description = "处理结果") String status,
        @Schema(description = "失败错误码") String errorCode,
        @Schema(description = "说明") String message
) {

    public static BatchItemResult success(UUID id) {
        return new BatchItemResult(id, "SUCCESS", null, null);
    }

    public static BatchItemResult skipped(UUID id, String message) {
        return new BatchItemResult(id, "SKIPPED", null, message);
    }

    public static BatchItemResult failed(UUID id, String errorCode, String message) {
        return new BatchItemResult(id, "FAILED", errorCode, message);
    }
}
