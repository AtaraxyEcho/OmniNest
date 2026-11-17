package com.omninest.modules.photos.event;

import java.util.UUID;

/**
 * 照片缩略图重生成任务事件，通过 RabbitMQ 发送到 Worker 异步处理。
 */
public record PhotoThumbnailRegenerationEvent(UUID taskId, UUID ownerUserId) {
}
