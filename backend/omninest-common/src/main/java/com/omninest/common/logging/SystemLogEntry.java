package com.omninest.common.logging;

import java.time.Instant;

/**
 * 管理界面可查询的单条运行日志摘要。
 *
 * @param id 进程内递增标识
 * @param timestamp 事件发生时间
 * @param level 日志级别
 * @param source 日志记录器名称
 * @param message 已脱敏且有长度上限的消息
 */
public record SystemLogEntry(
        long id,
        Instant timestamp,
        String level,
        String source,
        String message
) {
}
