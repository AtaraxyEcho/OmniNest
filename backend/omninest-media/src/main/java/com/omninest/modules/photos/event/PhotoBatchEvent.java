package com.omninest.modules.photos.event;

import java.util.UUID;

/**
 * 照片批量处理任务事件，通过 RabbitMQ 发送到 Worker 异步处理。
 */
public record PhotoBatchEvent(UUID taskId, UUID ownerUserId) {
}
