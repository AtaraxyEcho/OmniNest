package com.omninest.modules.music.event;

import java.util.UUID;

/**
 * 音乐扫描任务事件，通过 RabbitMQ 发送到 Worker 异步处理。
 */
public record MusicScanEvent(UUID jobId, UUID ownerUserId) {
}
