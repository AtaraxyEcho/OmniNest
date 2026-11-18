package com.omninest.modules.user.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import java.time.Instant;

/**
 * 管理端运行日志条目。
 *
 * @param id 进程内事件标识
 * @param timestamp 日志时间
 * @param level 日志级别
 * @param source 记录器名称
 * @param message 脱敏后的日志消息
 */
@Schema(description = "管理端运行日志条目")
public record AdminSystemLogDto(
        @Schema(description = "事件标识") long id,
        @Schema(description = "日志时间") Instant timestamp,
        @Schema(description = "日志级别", example = "WARN") String level,
        @Schema(description = "记录器名称") String source,
        @Schema(description = "脱敏后的日志消息") String message
) {
}
