package com.omninest.modules.media.service;

import java.time.Duration;
import java.time.Instant;

/**
 * 进度上报时间的服务端钳制。
 *
 * <p>跨设备进度以客户端记录时刻比较新旧；某台设备系统时钟快移（例如手动改成未来时间）
 * 会写出一条"永远最新"的记录，把其他设备的正常上报全部挡住。超过服务端当前时间
 * 60 秒的上报一律按服务端接收时间处理。</p>
 *
 * @author OmniNest
 */
public final class ProgressClockGuard {
    private static final Duration MAX_FUTURE_SKEW = Duration.ofSeconds(60);

    private ProgressClockGuard() {
    }

    /**
     * 钳制客户端上报时刻。
     *
     * @param reportedAt 客户端记录时刻，可为 null
     * @param serverNow 服务端当前时刻
     * @return 可用于比较的安全时刻
     */
    public static Instant clamp(Instant reportedAt, Instant serverNow) {
        if (reportedAt == null) {
            return serverNow;
        }
        if (reportedAt.isAfter(serverNow.plus(MAX_FUTURE_SKEW))) {
            return serverNow;
        }
        return reportedAt;
    }
}
