package com.omninest.modules.file.event;

import java.util.UUID;

/**
 * 外部存储导入请求事件，发布到 RabbitMQ 由 Worker 消费。
 */
public record ExternalImportRequestedEvent(UUID taskId) {
}
