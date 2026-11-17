package com.omninest.modules.file.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import java.time.Instant;

/**
 * 外部存储连接测试结果。
 *
 * @param success 是否连通
 * @param errorCode 失败错误码
 * @param message 可读消息
 * @param checkedAt 检查时间
 * @author OmniNest
 */
@Schema(description = "外部存储连接测试结果")
public record ExternalStorageTestResultDto(
        @Schema(description = "是否连通") boolean success,
        @Schema(description = "错误码") String errorCode,
        @Schema(description = "消息") String message,
        @Schema(description = "检查时间") Instant checkedAt
) {
}
